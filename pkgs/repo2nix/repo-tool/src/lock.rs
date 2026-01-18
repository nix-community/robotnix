use crate::fetch::{GitLsRemoteError, NixPrefetchGitError, git_ls_remote, nix_prefetch_git};
use repo_manifest::resolver::Project;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::io;
use std::path::{Path, PathBuf};
use thiserror::Error;
use tokio::fs;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Lock {
    // TODO proper [u8, 20] type for commit with (de)?serializer
    pub commit: String,
    pub nix_hash: String,
    pub path: PathBuf,
    pub date: u64,
}

pub fn is_commit_id(commit_id: &str) -> bool {
    commit_id.as_bytes().len() == 40 && commit_id.as_bytes().iter().all(|x| x.is_ascii_hexdigit())
}

#[derive(Debug, Error)]
pub enum UpdateLockError {
    #[error("error running `git ls-remote`")]
    GitLsRemote(#[from] GitLsRemoteError),
    #[error("error running `nix-prefetch-git`")]
    NixPrefetchGit(#[from] NixPrefetchGitError),
    #[error(
        "commit ids returned by `git ls-remote` and `nix-prefetch-git` for rev `{0}` do not match"
    )]
    CommitMismatch(String),
}
pub async fn update_lock(
    project: &Project,
    lock: &Option<Lock>,
    cleanup: bool,
) -> Result<(Lock, bool), UpdateLockError> {
    let current_commit = if is_commit_id(&project.repo_ref.revision) {
        project.repo_ref.revision.clone()
    } else {
        git_ls_remote(
            project.repo_ref.repo_url.as_str(),
            &project.repo_ref.revision,
        )
        .await?
    };

    let up_to_date = match lock {
        None => false,
        Some(l) => l.commit == current_commit,
    };

    if up_to_date {
        return Ok((lock.clone().unwrap(), false));
    }

    let fetch_output = nix_prefetch_git(
        &project.repo_ref.repo_url,
        &current_commit,
        project.repo_ref.fetch_lfs,
        project.repo_ref.fetch_submodules,
        cleanup,
    )
    .await?;

    if current_commit != fetch_output.rev {
        return Err(UpdateLockError::CommitMismatch(
            project.repo_ref.revision.clone(),
        ));
    }

    Ok((
        Lock {
            commit: fetch_output.rev,
            nix_hash: fetch_output.hash,
            path: fetch_output.path,
            date: fetch_output.date,
        },
        true,
    ))
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct LocksetEntry {
    pub project: Project,
    pub lock: Option<Lock>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Lockset {
    pub entries: BTreeMap<PathBuf, LocksetEntry>,
    pub path: PathBuf,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Lockfile {
    // BTreeMap because we want the ordering in the serialized lockfile to be consistent across
    // runs
    pub fetch_completed: bool,
    pub entries: BTreeMap<PathBuf, LocksetEntry>,
}

#[derive(Debug, Error)]
pub enum UpdateLocksetError {
    #[error("failed to update lock for `{project_path}`")]
    UpdateLock {
        #[source]
        error: UpdateLockError,
        project_path: PathBuf,
    },
    #[error("project `{0}` already present in lockfile")]
    DuplicateProject(PathBuf),
    #[error("path not found")]
    PathNotFound,
    #[error("failed to write lockfile")]
    WriteLockset(#[from] ReadWriteLockfileError),
}

#[derive(Debug, Error)]
pub enum ReadWriteLockfileError {
    #[error("input/output error")]
    IO(#[from] io::Error),
    #[error("error parsing file")]
    Parse(#[from] serde_json::Error),
}

#[derive(Debug, Error)]
pub enum EnsureStorePathError {
    #[error("project {0} not found in lockfile")]
    PathNotFound(PathBuf),
    #[error("project {0} not locked yet")]
    ProjectNotLocked(PathBuf),
    #[error("error checking whether store path {0} exists")]
    StorePathIO(#[from] io::Error),
    #[error("error running nix-prefetch-git")]
    NixPrefetchGit(#[from] NixPrefetchGitError),
}

impl Lockset {
    pub fn new(projects: &HashMap<PathBuf, Project>, path: &Path) -> Self {
        Lockset {
            entries: projects
                .iter()
                .map(|(path, project)| {
                    (
                        path.clone(),
                        LocksetEntry {
                            project: project.clone(),
                            lock: None,
                        },
                    )
                })
                .collect(),
            path: path.to_path_buf(),
        }
    }

    pub fn deactivate_all(&mut self) {
        for (_, entry) in self.entries.iter_mut() {
            entry.project.active = false;
        }
    }

    pub fn add_project(&mut self, mut project: Project) -> Result<(), UpdateLocksetError> {
        match self.entries.get_mut(&project.path) {
            Some(ref mut entry) => {
                if entry.project.active {
                    if entry.project.repo_ref != project.repo_ref {
                        return Err(UpdateLocksetError::DuplicateProject(project.path.clone()));
                    }

                    if entry.project.groups.len() == 0 || project.groups.len() == 0 {
                        entry.project.groups.append(&mut project.groups);
                    } else {
                        return Err(UpdateLocksetError::DuplicateProject(project.path.clone()));
                    }

                    if entry.project.linkfiles.len() == 0 || project.linkfiles.len() == 0 {
                        entry.project.linkfiles.append(&mut project.linkfiles);
                    } else {
                        return Err(UpdateLocksetError::DuplicateProject(project.path.clone()));
                    }

                    if entry.project.copyfiles.len() == 0 || project.copyfiles.len() == 0 {
                        entry.project.copyfiles.append(&mut project.copyfiles);
                    } else {
                        return Err(UpdateLocksetError::DuplicateProject(project.path.clone()));
                    }

                    for cat in project.categories.iter() {
                        entry.project.categories.insert(cat.clone());
                    }
                    entry.project.active = true;
                } else {
                    if entry.project.repo_ref != project.repo_ref {
                        entry.lock = None;
                    }
                    entry.project = project;
                }
            }
            None => {
                self.entries.insert(
                    project.path.clone(),
                    LocksetEntry {
                        project: project,
                        lock: None,
                    },
                );
            }
        }

        Ok(())
    }

    pub async fn read_from_file(path: &Path) -> Result<Self, ReadWriteLockfileError> {
        let json = fs::read(path).await.map_err(ReadWriteLockfileError::IO)?;
        let lockfile: Lockfile =
            serde_json::from_reader(json.as_slice()).map_err(ReadWriteLockfileError::Parse)?;
        Ok(Lockset {
            entries: lockfile.entries,
            path: path.to_path_buf(),
        })
    }

    pub async fn write(&self, fetch_completed: bool) -> Result<(), ReadWriteLockfileError> {
        let json = serde_json::to_vec_pretty(&Lockfile {
            entries: self.entries.clone(),
            fetch_completed: fetch_completed,
        })
        .map_err(ReadWriteLockfileError::Parse)?;
        let tmp_path = self.path.with_extension(".tmp");
        fs::write(&tmp_path, json.as_slice()).await?;
        fs::rename(&tmp_path, &self.path).await?;
        Ok(())
    }

    pub async fn update(
        &mut self,
        project_path: &Path,
        cleanup: bool,
    ) -> Result<(), UpdateLocksetError> {
        let entry = self
            .entries
            .get_mut(project_path)
            .ok_or(UpdateLocksetError::PathNotFound)?;
        let (new_lock, updated) = update_lock(&entry.project, &entry.lock, cleanup)
            .await
            .map_err(|e| UpdateLocksetError::UpdateLock {
                project_path: project_path.to_path_buf(),
                error: e,
            })?;

        entry.lock = Some(new_lock);

        if updated {
            self.write(false).await?;
        }

        Ok(())
    }

    pub async fn update_all(&mut self, cleanup: bool) -> Result<(), UpdateLocksetError> {
        let paths: Vec<_> = self.entries.keys().cloned().collect();
        for (i, path) in paths.iter().enumerate() {
            if self.entries.get(path).unwrap().project.active {
                eprintln!(
                    "Updating lock for `{}` ({}/{})",
                    path.display(),
                    i + 1,
                    paths.len()
                );
                self.update(path, cleanup).await?;
            }
        }
        Ok(())
    }

    pub async fn ensure_store_path(&self, project_path: &Path) -> Result<(), EnsureStorePathError> {
        let entry = self
            .entries
            .get(project_path)
            .ok_or(EnsureStorePathError::PathNotFound(
                project_path.to_path_buf(),
            ))?;
        let repo_ref = &entry.project.repo_ref;
        let lock = &entry
            .lock
            .as_ref()
            .ok_or(EnsureStorePathError::ProjectNotLocked(
                project_path.to_path_buf(),
            ))?;

        if !fs::try_exists(&lock.path).await? {
            nix_prefetch_git(
                &repo_ref.repo_url,
                &lock.commit,
                repo_ref.fetch_lfs,
                repo_ref.fetch_submodules,
                false,
            )
            .await?;
        }

        Ok(())
    }
}
