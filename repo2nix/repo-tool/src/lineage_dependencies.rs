use std::io;
use std::path::{Path, PathBuf};
use std::collections::BTreeMap;
use tokio::fs;
use serde::{Serialize, Deserialize};
use serde_json;
use thiserror::Error;
use repo_manifest::resolver::{
    Manifest,
    GitRepoRef,
    join_repo_url,
};
use crate::fetch::{
    nix_prefetch_git,
    NixPrefetchGitError,
    git_ls_remote,
    GitLsRemoteError,
};
use crate::lineage_devices::{
    hudson_to_device_repo_branch,
    DeviceInfo,
};

#[derive(Debug, PartialEq, Eq)]
pub enum LineageDeps {
    MissingBranch,
    NoLineageDependenciesFile,
    Some(Vec<PathBuf>),
}

#[derive(Debug, PartialEq)]
pub struct LineageProject {
    pub repo_ref: GitRepoRef,
    pub path: PathBuf,
    pub devices: Vec<String>,
    pub lineage_deps: Option<LineageDeps>,
}

#[derive(Debug, Error)]
pub enum MergeLineageDevicesError {
    #[error("device info for device `{0}` is inconsistent across device files")]
    InconsistentDeviceInfo(String),
    #[error("branch `{1}` of device `{0}` is defined several times in device files")]
    DuplicateBranch(String, String),
}

pub fn merge_lineage_devices(devices: &mut BTreeMap<String, DeviceInfo>, new_devices: BTreeMap<String, DeviceInfo>) -> Result<(), MergeLineageDevicesError> {
    for (name, new_device) in new_devices {
        match devices.get_mut(&name) {
            None => {
                devices.insert(name, new_device);
            },
            Some(device) => {
                if device.name != new_device.name ||
                    device.vendor != new_device.vendor ||
                    device.build_type != new_device.build_type ||
                    device.default_branch != new_device.default_branch ||
                    device.period != new_device.period {
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
            },
        }
    }
    Ok(())
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LineageDep {
    target_path: PathBuf,
    repository: String,
    remote: Option<String>,
    branch: Option<String>,
}

#[derive(Debug, Error)]
pub enum PrefetchLineageDepsError {
    #[error("`git ls-remote` failed")]
    LsRemote(GitLsRemoteError),
    #[error("`nix-prefetch-git` failed")]
    Fetch(NixPrefetchGitError),
    #[error("failed reading `lineage.dependencies` from device repo")]
    IO(#[from] io::Error),
    #[error("failed to parse")]
    Parse(#[from] serde_json::Error),
    #[error("failed to resolve deps of repo {0}")]
    Resolve(PathBuf, #[source] ResolveLineageDepsError),
    #[error("project `{0}` appeared in multiple `lineage.dependencies` files with conflicting repo names and branches")]
    ConflictingEntries(PathBuf),
}

#[derive(Debug, Error)]
pub enum ResolveLineageDepsError {
    #[error("unknown remote `{0}` for dep `{1}`")]
    UnknownRemote(String, PathBuf),
    #[error("missing remote for dep `{0}`, and no default remote was set in manifest")]
    MissingRemote(PathBuf),
    #[error("default remote in manifest has no revision set, can't infer branch of dependency `{0}`")]
    RemoteMissingRevision(PathBuf),
}


pub fn resolve_lineage_dependencies(manifest: &Manifest, lineage_deps: &[LineageDep], devices: &[String]) -> Result<Vec<LineageProject>, ResolveLineageDepsError> {
    let mut project_deps = vec![];
    for dep in lineage_deps {
        let remote = match &dep.remote {
            Some(remote_name) => manifest.remotes.get(remote_name).ok_or(ResolveLineageDepsError::UnknownRemote(
                    remote_name.to_string(),
                    dep.target_path.clone(),
            ))?,
            None => &manifest.default_remote.as_ref().ok_or(ResolveLineageDepsError::MissingRemote(
                    dep.target_path.clone(),
            ))?,
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
                let rev = remote.revision.as_ref().ok_or(ResolveLineageDepsError::RemoteMissingRevision(
                        dep.target_path.clone(),
                ))?;
                match rev.strip_prefix("refs/heads/") {
                    Some(branch) => format!("refs/heads/{}", hudson_to_device_repo_branch(branch)),
                    None => rev.clone(),
                }
            },
        };

        // The upstream mechanism for choosing whether to prepend `LineageOS/` to the repo name
        // defined in the `repository` field is pretty broken: it just checks whether the remote
        // name starts with `aosp-`, and prepends `LineageOS/` to the repo name and sets the remote
        // to `github` if it isn't. This breaks once you add in remotes other than `github` and the
        // `aosp-*` ones. It's probably for the best to not try to fix this behaviour and to just
        // consistently replicate it.
        //
        // Source:
        // https://github.com/LineageOS/android_vendor_lineage/blob/80189ed8cc193dc2ca51a7eb46a7c648a3ee4eda/build/tools/roomservice.py#L183
        let repo_name = if !remote.name.starts_with("aosp-") {
            format!("LineageOS/{}", dep.repository)
        } else {
            dep.repository.clone()
        };
        project_deps.push(LineageProject {
            path: dep.target_path.clone(),
            repo_ref: GitRepoRef {
                repo_url: join_repo_url(&remote.url, &repo_name),
                revision: revision,
                fetch_lfs: false,
                fetch_submodules: false,
            },
            devices: devices.iter().cloned().collect(),
            lineage_deps: None,
        });
    }

    Ok(project_deps)
}

pub async fn prefetch_lineage_dependencies(devices: &BTreeMap<String, DeviceInfo>, manifest: &Manifest, branch: &str) -> Result<Vec<LineageProject>, PrefetchLineageDepsError> {
    eprintln!("Building LineageOS-specific dependency tree...");
    let mut projects: Vec<LineageProject> = devices
        .iter()
        .filter(|(_, x)| x.branches.contains_key(branch))
        .map(|(k, v)| LineageProject {
            repo_ref: v.branches.get(branch).unwrap().clone(),
            path: Path::new("device").join(&v.vendor).join(&v.name),
            devices: vec![k.clone()],
            lineage_deps: None,
        })
        .collect();

    let mut i = 0;
    loop {
        let (dep_paths, deps) = {
            let project = match projects.get(i) {
                Some(p) => p,
                None => break,
            };

            match git_ls_remote(
                &project.repo_ref.repo_url.as_str(),
                &project.repo_ref.revision
            ).await {
                Ok(commit) => {
                    let fetch = nix_prefetch_git(
                        &project.repo_ref.repo_url,
                        &commit,
                        project.repo_ref.fetch_lfs,
                        project.repo_ref.fetch_submodules,
                    )
                        .await
                        .map_err(PrefetchLineageDepsError::Fetch)?;

                    if !fs::try_exists(&fetch.path.join("lineage.dependencies")).await.map_err(PrefetchLineageDepsError::IO)? {
                        (LineageDeps::NoLineageDependenciesFile, None)
                    } else {
                        let lineage_deps: Vec<LineageDep> = serde_json::from_slice(
                            &fs::read(&fetch.path.join("lineage.dependencies")).await.map_err(PrefetchLineageDepsError::IO)?
                        )
                            .map_err(PrefetchLineageDepsError::Parse)?;

                        let ldeps = resolve_lineage_dependencies(manifest, &lineage_deps, &project.devices)
                            .map_err(|e| PrefetchLineageDepsError::Resolve(project.path.clone(), e))?;
                        (LineageDeps::Some(ldeps.iter().map(|x| x.path.clone()).collect()), Some(ldeps))
                    }
                },
                Err(GitLsRemoteError::RevNotFound) => (LineageDeps::MissingBranch, None),
                Err(e) => return Err(PrefetchLineageDepsError::LsRemote(e)),
            }
        };
        projects[i].lineage_deps = Some(dep_paths);

        if let Some(deps) = deps {
            for dep in deps {
                match projects.iter_mut().find(|x| x.path == dep.path) {
                    Some(old_project) => {
                        if old_project.repo_ref != dep.repo_ref {
                            return Err(PrefetchLineageDepsError::ConflictingEntries(dep.path.clone()));
                        } else {
                            for device in dep.devices {
                                if !old_project.devices.contains(&device) {
                                    old_project.devices.push(device);
                                }
                            }
                        }
                    },
                    None => {
                        projects.push(dep);
                    },
                }
            }
        }
        i += 1;
    }

    eprintln!("Done building LineageOS-specific dependency tree.");
    Ok(projects)
}
