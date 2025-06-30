use std::io;
use std::path::{Path, PathBuf};
use std::collections::BTreeMap;
use tokio::fs;
use serde::{Serialize, Deserialize};
use serde_json;
use thiserror::Error;
use repo_manifest::resolver::{
    Project,
    Category,
    Manifest,
    GitRepoRef,
    join_repo_url,
};
use crate::fetch::{
    nix_prefetch_git,
    NixPrefetchGitError,
};
use crate::lineage_devices::{
    hudson_to_device_repo_branch,
    DeviceInfo,
};

pub fn add_lineage_devices(manifest: &mut Manifest, devices: &BTreeMap<String, DeviceInfo>, branch: &str) {
    for (name, device) in devices.iter() {
        if let Some(repo_ref) = device.branches.get(branch) {
            let path = Path::new("device").join(&device.vendor).join(name);
            manifest.projects.insert(path.clone(), Project {
                path: path,
                groups: vec![],
                linkfiles: vec![],
                copyfiles: vec![],
                repo_ref: repo_ref.clone(),
                categories: vec![Category::DeviceSpecific(name.clone())],
                lineage_deps: Some(None),
            });
        }
    }
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
    #[error("`nix-prefetch-git` failed")]
    Fetch(NixPrefetchGitError),
    #[error("failed reading `lineage.dependencies` from device repo")]
    IO(#[from] io::Error),
    #[error("failed to parse")]
    Parse(#[from] serde_json::Error),
    #[error("failed to resolve deps")]
    Resolve(ResolveLineageDepsError),
}

#[derive(Debug, Error)]
pub enum ResolveLineageDepsError {
    #[error("unknown remote `{0}` for dep `{1}` in `lineage.dependencies` of repo `{2}`")]
    UnknownRemote(String, PathBuf, PathBuf),
    #[error("missing remote for dep `{0}` in repo `{1}`, and no default remote was set in manifest")]
    MissingRemote(PathBuf, PathBuf),
    #[error("no default remote was set in manifest from which we could infer the branch for `{0}`")]
    MissingDefaultRemote(PathBuf),
    #[error("default remote in manifest has no revision set, can't infer branch of dependency `{0}` in repo `{1}`")]
    DefaultRemoteMissingRevision(PathBuf, PathBuf),
}


pub fn resolve_lineage_dependencies(manifest: &Manifest, path: &Path, lineage_deps: &[LineageDep], categories: &[Category]) -> Result<Vec<Project>, ResolveLineageDepsError> {
    let mut project_deps = vec![];
    for dep in lineage_deps {
        let remote = match &dep.remote {
            Some(remote_name) => manifest.remotes.get(remote_name).ok_or(ResolveLineageDepsError::UnknownRemote(
                    remote_name.to_string(),
                    dep.target_path.clone(),
                    path.to_path_buf(),
            ))?,
            None => &manifest.default_remote.as_ref().ok_or(ResolveLineageDepsError::MissingRemote(
                    dep.target_path.clone(),
                    path.to_path_buf(),
            ))?,
        };

        // This behaviour is highly dubious - we should check the default branch of the
        // remote of the dependency in question, and not the default branch of the default
        // remote. But the LineageOS roomservice.py script does it that way, so we have
        // to replicate its erroneous behaviour.
        let revision = match &dep.branch {
            Some(b) => format!("refs/heads/{}", b),
            None => {
                let default_remote = manifest.default_remote.as_ref().ok_or(ResolveLineageDepsError::MissingDefaultRemote(dep.target_path.clone()))?;
                let rev = default_remote.revision.as_ref().ok_or(ResolveLineageDepsError::DefaultRemoteMissingRevision(
                        dep.target_path.clone(),
                        path.to_path_buf(),
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
        // https://github.com/LineageOS/android_vendor_lineage/blob/80189ed8cc193dc2ca51a7eb46a7c648a3ee4eda/build/tools/roomservice.py#L183)
        let repo_name = if remote.name == "github" {
            format!("LineageOS/{}", dep.repository)
        } else {
            dep.repository.clone()
        };
        project_deps.push(Project {
            path: dep.target_path.clone(),
            groups: vec![],
            linkfiles: vec![],
            copyfiles: vec![],
            repo_ref: GitRepoRef {
                repo_url: join_repo_url(&remote.url, &repo_name),
                revision: revision,
                fetch_lfs: false,
                fetch_submodules: false,
            },
            categories: categories.iter().map(|x| x.clone()).collect(),
            lineage_deps: Some(None),
        });
    }

    Ok(project_deps)
}

pub async fn prefetch_lineage_dependencies(manifest: &mut Manifest) -> Result<(), PrefetchLineageDepsError> {
    loop {
        let mut done = true;
        let mut projects_to_add = vec![];
        let current_paths: Vec<_> = manifest.projects.keys().map(|x| x.clone()).collect();
        for path in current_paths.iter() {
            let project_deps = {
                let project = manifest.projects.get(path).unwrap();
                if let Some(None) = project.lineage_deps {
                    done = false;
                    let fetch = nix_prefetch_git(
                        &project.repo_ref.repo_url,
                        &project.repo_ref.revision,
                        project.repo_ref.fetch_lfs,
                        project.repo_ref.fetch_submodules,
                    )
                        .await
                        .map_err(PrefetchLineageDepsError::Fetch)?;

                    if !fs::try_exists(&fetch.path.join("lineage.dependencies")).await.map_err(PrefetchLineageDepsError::IO)? {
                        None
                    } else {
                        let lineage_deps: Vec<LineageDep> = serde_json::from_slice(
                            &fs::read(&fetch.path.join("lineage.dependencies")).await.map_err(PrefetchLineageDepsError::IO)?
                        )
                            .map_err(PrefetchLineageDepsError::Parse)?;

                        Some(resolve_lineage_dependencies(manifest, path, &lineage_deps, &project.categories)
                            .map_err(PrefetchLineageDepsError::Resolve)?)
                    }
                } else {
                    continue;
                }
            };

            let project = manifest.projects.get_mut(path).unwrap();
            if let Some(mut project_deps) = project_deps {
                project.lineage_deps = Some(Some(
                    project_deps.iter().map(|x| x.path.clone()).collect()
                ));
                projects_to_add.append(&mut project_deps);
            } else {
                project.lineage_deps = None;
            }
        }
        if done {
            break;
        }

        for project in projects_to_add {
            match manifest.projects.get_mut(&project.path) {
                Some(other_project) => {
                    if project.groups == other_project.groups
                        && project.linkfiles == other_project.linkfiles
                        && project.copyfiles == other_project.copyfiles
                        && project.repo_ref == other_project.repo_ref {
                            for cat in project.categories {
                                if !other_project.categories.contains(&cat) {
                                    other_project.categories.push(cat);
                                }
                            }
                    }
                },
                None => {
                    manifest.projects.insert(project.path.clone(), project);
                },
            }
        }
    }

    Ok(())
}
