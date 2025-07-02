use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::io;
use tokio::fs;
use thiserror::Error;
use serde::{Serialize, Deserialize};
use repo_manifest::resolver::{
    Project,
};
use crate::fetch::{
    nix_prefetch_git,
    git_ls_remote,
    NixPrefetchGitError,
    GitLsRemoteError,
};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Lock {
    // TODO proper [u8, 20] type for commit with (de)?serializer
    pub commit: String,
    pub nix_hash: String,
    pub path: PathBuf,
    pub date: u64,
}

#[derive(Debug, Error)]
pub enum UpdateLockError {
    #[error("error running `git ls-remote`")]
    GitLsRemote(#[from] GitLsRemoteError),
    #[error("error running `nix-prefetch-git`")]
    NixPrefetchGit(#[from] NixPrefetchGitError),
    #[error("commit ids returned by `git ls-remote` and `nix-prefetch-git` for rev `{0}` do not match")]
    CommitMismatch(String),
}

pub fn is_commit_id(commit_id: &str) -> bool {
    if commit_id.as_bytes().len() == 40 {
        if commit_id.as_bytes().iter().all(|x| x.is_ascii_hexdigit()) {
            true
        } else {
            false
        }
    } else {
        false
    }
}

pub async fn update_lock(project: &Project, lock: &Option<Lock>) -> Result<Lock, UpdateLockError> {
    let current_commit = if is_commit_id(&project.repo_ref.revision) {
        project.repo_ref.revision.clone()
    } else {
        git_ls_remote(project.repo_ref.repo_url.as_str(), &project.repo_ref.revision)
            .await
            .map_err(UpdateLockError::GitLsRemote)?
    };

    let refetch = match lock {
        None => true,
        Some(l) => l.commit != current_commit,
    };

    if refetch {
        let fetch_output = nix_prefetch_git(
            &project.repo_ref.repo_url,
            &current_commit,
            project.repo_ref.fetch_lfs,
            project.repo_ref.fetch_submodules,
        )
            .await
            .map_err(UpdateLockError::NixPrefetchGit)?;

        if current_commit != fetch_output.rev {
            return Err(UpdateLockError::CommitMismatch(project.repo_ref.revision.clone()));
        }

        Ok(Lock {
            commit: fetch_output.rev,
            nix_hash: fetch_output.hash,
            path: fetch_output.path,
            date: fetch_output.date,
        })
    } else {
        Ok(lock.clone().unwrap())
    }
}


#[derive(Debug, Serialize, Deserialize)]
pub struct LockfileEntry {
    pub project: Project,
    pub lock: Option<Lock>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Lockfile {
    // BTreeMap because we want the ordering in the serialized lockfile to be consistent across
    // runs
    pub entries: BTreeMap<PathBuf, LockfileEntry>,
    pub path: PathBuf,
}

#[derive(Debug, Error)]
pub enum UpdateLockfileError {
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
    WriteLockfile(ReadWriteLockfileError),
}

#[derive(Debug, Error)]
pub enum ReadWriteLockfileError {
    #[error("input/output error")]
    IO(io::Error),
    #[error("error parsing file")]
    Parse(serde_json::Error),
}

impl Lockfile {
    pub fn new(projects: &HashMap<PathBuf, Project>, path: &Path) -> Self {
        Lockfile {
            entries: projects
                .iter()
                .map(|(path, project)| (path.clone(), LockfileEntry {
                    project: project.clone(),
                    lock: None
                }))
                .collect(),
            path: path.to_path_buf(),
        }
    }

    pub fn add_project(&mut self, project: Project, allow_modify: bool) -> Result<(), UpdateLockfileError> {
        match self.entries.get_mut(&project.path) {
            Some(ref mut entry) => {
                if entry.project.repo_ref != project.repo_ref {
                    if allow_modify {
                    entry.lock = None;
                        entry.project.repo_ref = project.repo_ref;
                    } else {
                        return Err(UpdateLockfileError::DuplicateProject(project.path.clone()));
                    }
                }
                for cat in project.categories {
                    if !entry.project.categories.contains(&cat) {
                        entry.project.categories.push(cat);
                    }
                }
            },
            None => {
                self.entries.insert(project.path.clone(), LockfileEntry {
                    project: project,
                    lock: None,
                });
            },
        }

        Ok(())
    }

    pub async fn read_from_file(path: &Path) -> Result<Self, ReadWriteLockfileError> {
        let json = fs::read(path).await.map_err(ReadWriteLockfileError::IO)?;
        Ok(Lockfile {
            entries: serde_json::from_reader(json.as_slice()).map_err(ReadWriteLockfileError::Parse)?,
            path: path.to_path_buf(),
        })
    }

    pub async fn write(&self) -> Result<(), ReadWriteLockfileError> {
        let json = serde_json::to_vec_pretty(&self.entries).map_err(ReadWriteLockfileError::Parse)?;
        fs::write(&self.path, json.as_slice()).await.map_err(ReadWriteLockfileError::IO)
    }

    pub async fn update(&mut self, project_path: &Path) -> Result<(), UpdateLockfileError> {
        let entry = self.entries.get_mut(project_path).ok_or(UpdateLockfileError::PathNotFound)?;
        entry.lock = Some(
            update_lock(
                &entry.project,
                &entry.lock
            )
            .await
            .map_err(|e| UpdateLockfileError::UpdateLock {
                project_path: project_path.to_path_buf(),
                error: e,
            })?
        );

        self.write().await.map_err(UpdateLockfileError::WriteLockfile)?;

        Ok(())
    }

    pub async fn update_all(&mut self) -> Result<(), UpdateLockfileError> {
        let mut paths: Vec<_> = self.entries.keys().cloned().collect();
        paths.sort();
        for (i, path) in paths.iter().enumerate() {
            eprintln!("Updating lock for `{}` ({}/{})", path.display(), i+1, paths.len());
            self.update(path).await?;
            self.write().await.map_err(UpdateLockfileError::WriteLockfile)?;
        }
        Ok(())
    }
}
