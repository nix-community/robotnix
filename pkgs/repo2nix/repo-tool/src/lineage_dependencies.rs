use crate::fetch::GitLsRemoteError;
use crate::lineage_devices::{DeviceInfo, hudson_to_device_repo_branch};
use crate::lock::{EnsureStorePathError, Lockset, UpdateLockError, UpdateLocksetError};
use repo_manifest::resolver::{
    Category, GitRepoRef, LineageDeps, Manifest, Project, join_repo_url,
};
use repo_manifest::resolver::{
    RecursivelyReadManifestFilesError, ResolveManifestError, merge_manifests, resolve_manifest,
};
use repo_manifest::xml::{Manifest as XMLManifest, ManifestReadFileError, read_manifest_file};
use serde::{Deserialize, Serialize};
use serde_json;
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::{Path, PathBuf};
use thiserror::Error;
use tokio::fs;
use url::Url;

#[derive(Debug, Error)]
pub enum MergeLineageDevicesError {
    #[error("device info for device `{0}` is inconsistent across device files")]
    InconsistentDeviceInfo(String),
    #[error("branch `{1}` of device `{0}` is defined several times in device files")]
    DuplicateBranch(String, String),
}

pub fn merge_lineage_devices(
    devices: &mut BTreeMap<String, DeviceInfo>,
    new_devices: BTreeMap<String, DeviceInfo>,
) -> Result<(), MergeLineageDevicesError> {
    for (name, new_device) in new_devices {
        match devices.get_mut(&name) {
            None => {
                devices.insert(name, new_device);
            }
            Some(device) => {
                if device.name != new_device.name
                    || device.vendor != new_device.vendor
                    || device.build_type != new_device.build_type
                    || device.default_branch != new_device.default_branch
                    || device.period != new_device.period
                {
                    return Err(MergeLineageDevicesError::InconsistentDeviceInfo(name));
                } else {
                    for (branch, dev_repo) in new_device.branches {
                        if !device.branches.contains_key(&branch) {
                            device.branches.insert(branch, dev_repo);
                        } else {
                            return Err(MergeLineageDevicesError::DuplicateBranch(name, branch));
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LineageDep {
    #[serde(rename = "type")]
    dep_type: Option<String>,
    target_path: Option<PathBuf>,
    repository: Option<String>,
    remote: Option<String>,
    branch: Option<String>,
    version: Option<String>,
}

#[derive(Debug, Error)]
pub enum PrefetchLineageDepsError {
    #[error("updating lock failed")]
    Lock(#[from] UpdateLocksetError),
    #[error("error ensuring that the Nix store path exists")]
    EnsureStorePath(#[from] EnsureStorePathError),
    #[error("failed reading `lineage.dependencies` from device repo")]
    IO(#[from] io::Error),
    #[error("failed to parse")]
    Parse(#[from] serde_json::Error),
    #[error("failed to resolve deps of repo {0}")]
    Resolve(PathBuf, #[source] ResolveLineageDepsError),
}

#[derive(Debug, Error)]
pub enum ResolveLineageDepsError {
    #[error("unknown remote `{0}` for dep `{1}`")]
    UnknownRemote(String, PathBuf),
    #[error("missing remote for dep `{0}`, and no default remote was set in manifest")]
    MissingRemote(PathBuf),
    #[error(
        "default remote in manifest has no revision set, can't infer branch of dependency `{0}`"
    )]
    RemoteMissingRevision(PathBuf),
    #[error("error reading kernel manifest file")]
    ReadKernelManifest(#[source] ManifestReadFileError),
    #[error("error resolving kernel manifest remotes")]
    ResolveManifest(#[from] ResolveManifestError),
    #[error("error merging Muppets manifest with main manifest")]
    MergeKernelManifest(#[source] RecursivelyReadManifestFilesError),
}

pub async fn resolve_lineage_dependencies(
    manifest: &Manifest,
    lineage_deps: &[LineageDep],
    root_path: &PathBuf,
    url: &Url,
    manifest_xml: &XMLManifest,
) -> Result<Vec<Project>, ResolveLineageDepsError> {
    let mut project_deps = vec![];
    for dep in lineage_deps {
        let dep_type = match &dep.dep_type {
            // Default dependency type is "project"
            None => "project",
            Some(dep_type) => dep_type.as_str(),
        };

        let version = &dep.version.clone().unwrap_or_default();
        let target_path = &dep.target_path.clone().unwrap_or_default();
        let repository = &dep.repository.clone().unwrap_or_default();

        if dep_type == "kernel" {
            let mut manifest_xml = manifest_xml.clone();
            let kernel_manifest_path = format!("snippets/kernel-{}.xml", version);
            let kernel_manifest_xml = read_manifest_file(&root_path.join(kernel_manifest_path))
                .await
                .map_err(ResolveLineageDepsError::ReadKernelManifest)?;
            merge_manifests(&mut manifest_xml, &kernel_manifest_xml)
                .map_err(ResolveLineageDepsError::MergeKernelManifest)?;
            let manifest = resolve_manifest(&manifest_xml, &url)?;
            for project in kernel_manifest_xml.projects {
                let project = match manifest.projects.get(&project.path.unwrap_or_default()) {
                    None => continue,
                    Some(project) => project,
                };
                project_deps.push(project.clone());
            }
        } else {
            let remote = match &dep.remote {
                Some(remote_name) => manifest.remotes.get(remote_name).ok_or(
                    ResolveLineageDepsError::UnknownRemote(
                        remote_name.to_string(),
                        target_path.clone(),
                    ),
                )?,
                None => &manifest
                    .default_remote
                    .as_ref()
                    .ok_or(ResolveLineageDepsError::MissingRemote(target_path.clone()))?,
            };

            // This behaviour is highly dubious - we should check the default branch of the
            // remote of the dependency in question, and not the default branch of the default
            // remote. But the LineageOS roomservice.py script does it that way, so we have
            // to replicate its erroneous behaviour.
            //
            // Source:
            // https://github.com/LineageOS/android_vendor_lineage/blob/80189ed8cc193dc2ca51a7eb46a7c648a3ee4eda/build/tools/roomservice.py#L220
            let revision = match &dep.branch {
                Some(b) => format!("refs/heads/{}", b),
                None => {
                    let rev = remote.revision.as_ref().ok_or(
                        ResolveLineageDepsError::RemoteMissingRevision(target_path.clone()),
                    )?;
                    match rev.strip_prefix("refs/heads/") {
                        Some(branch) => {
                            format!("refs/heads/{}", hudson_to_device_repo_branch(branch))
                        }
                        None => rev.clone(),
                    }
                }
            };

            // The upstream mechanism for choosing whether to prepend `LineageOS/` to the repo name
            // defined in the `repository` field is pretty broken: it just checks whether the remote
            // name starts with `aosp-`, and if it does't, it prepends `LineageOS/` to the repo name
            // and then changes the remote to `github` from whatever it else was previously. This
            // breaks once you add in remotes other than `github` and the `aosp-*` ones. It's probably
            // for the best to not try to fix this behaviour and to just consistently replicate it.
            //
            // Source:
            // https://github.com/LineageOS/android_vendor_lineage/blob/80189ed8cc193dc2ca51a7eb46a7c648a3ee4eda/build/tools/roomservice.py#L183
            let repo_name = if !remote.name.starts_with("aosp-") {
                format!("LineageOS/{}", repository.clone())
            } else {
                repository.clone()
            };
            project_deps.push(Project {
                path: target_path.clone(),
                groups: vec![],
                linkfiles: vec![],
                copyfiles: vec![],
                repo_ref: GitRepoRef {
                    repo_url: join_repo_url(&remote.url, &repo_name),
                    revision: revision,
                    fetch_lfs: true,
                    fetch_submodules: false,
                },
                categories: BTreeSet::new(),
                lineage_deps: None,
                active: true,
            });
        };
    }

    Ok(project_deps)
}

fn recursively_propagate_categories(lockfile: &mut Lockset, path: &Path) {
    let (deps, cats) = {
        let project = &lockfile.entries.get(path).unwrap().project;
        match &project.lineage_deps {
            Some(LineageDeps::Some(deps)) => (Some(deps.clone()), project.categories.clone()),
            _ => (None, project.categories.clone()),
        }
    };

    if let Some(deps) = deps {
        for dep in deps {
            {
                let project = &mut lockfile.entries.get_mut(&dep).unwrap().project;
                for cat in cats.iter() {
                    project.categories.insert(cat.clone());
                }
            }
            recursively_propagate_categories(lockfile, &dep);
        }
    }
}

pub async fn prefetch_lineage_dependencies(
    lockfile: &mut Lockset,
    devices: &BTreeMap<String, DeviceInfo>,
    manifest: &Manifest,
    branch: &str,
    root_path: &PathBuf,
    url: &Url,
    manifest_xml: &XMLManifest,
) -> Result<(), PrefetchLineageDepsError> {
    eprintln!("Building LineageOS-specific dependency tree...");

    let mut fetch_queue = vec![];
    for (_name, device) in devices.iter() {
        match device.branches.get(branch) {
            Some(repo_ref) => {
                let path = Path::new("device").join(&device.vendor).join(&device.name);
                lockfile.add_project(Project {
                    path: path.clone(),
                    groups: vec![],
                    linkfiles: vec![],
                    copyfiles: vec![],
                    repo_ref: repo_ref.clone(),
                    categories: {
                        let mut cats = BTreeSet::new();
                        cats.insert(Category::DeviceSpecific(device.name.clone()));
                        cats
                    },
                    lineage_deps: None,
                    active: true,
                })?;
                fetch_queue.push(path);
            }
            None => (),
        }
    }
    let device_repos = fetch_queue.clone();

    let mut i = 0;
    loop {
        let path = match fetch_queue.get(i) {
            Some(p) => p.clone(),
            None => break,
        };

        eprintln!("Fetching LineageOS dependencies for {}...", path.display());

        let (new_deps, new_projects) = match lockfile.update(&path).await {
            Ok(()) => {
                lockfile.ensure_store_path(&path).await?;

                let store_path = &lockfile
                    .entries
                    .get(&path)
                    .as_ref()
                    .unwrap()
                    .lock
                    .as_ref()
                    .unwrap()
                    .path;

                if !fs::try_exists(&store_path.join("lineage.dependencies")).await? {
                    (LineageDeps::NoLineageDependenciesFile, None)
                } else {
                    let lineage_deps: Vec<LineageDep> = serde_json::from_slice(
                        &fs::read(&store_path.join("lineage.dependencies")).await?,
                    )?;

                    let ldeps = resolve_lineage_dependencies(
                        manifest,
                        &lineage_deps,
                        &root_path,
                        &url,
                        &manifest_xml,
                    )
                    .await
                    .map_err(|e| PrefetchLineageDepsError::Resolve(path.clone(), e))?;
                    (
                        LineageDeps::Some(ldeps.iter().map(|x| x.path.clone()).collect()),
                        Some(ldeps),
                    )
                }
            }
            Err(UpdateLocksetError::UpdateLock {
                project_path: _,
                error: UpdateLockError::GitLsRemote(GitLsRemoteError::RevNotFound),
            }) => (LineageDeps::MissingBranch, None),
            Err(e) => return Err(PrefetchLineageDepsError::Lock(e)),
        };

        {
            let project = &mut lockfile.entries.get_mut(&path).unwrap().project;
            project.lineage_deps = Some(new_deps);
        }

        if let Some(new_projects) = new_projects {
            for new_project in new_projects {
                if !fetch_queue.contains(&new_project.path) {
                    fetch_queue.push(new_project.path.clone());
                }
                if !lockfile.entries.contains_key(&new_project.path) {
                    lockfile.add_project(new_project)?;
                }
            }
        }
        i += 1;
    }

    // Propagate device categories upwards through the dependency tree
    for device_repo in device_repos {
        recursively_propagate_categories(lockfile, &device_repo);
    }

    eprintln!("Done building LineageOS-specific dependency tree.");
    Ok(())
}

pub fn cleanup_failed_lineage_deps(lockfile: &mut Lockset) {
    let paths_to_cleanup: Vec<_> = lockfile
        .entries
        .iter()
        .filter(|(_, x)| x.project.lineage_deps == Some(LineageDeps::MissingBranch))
        .map(|(path, _)| path.clone())
        .collect();

    for path in paths_to_cleanup {
        lockfile.entries.remove(&path);
    }
}
