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

pub async fn update_lock(project: &Project, lock: &Option<Lock>) -> Result<Lock, UpdateLockError> {
    let (refetch, current_commit) = match lock {
        Some(l) => {
            let current_commit = git_ls_remote(project.repo_ref.repo_url.as_str(), &project.repo_ref.revision)
                .await
                .map_err(UpdateLockError::GitLsRemote)?;

            (l.commit == current_commit, Some(current_commit))
        },
        None => (true, None),
    };

    if refetch {
        let fetch_output = nix_prefetch_git(&project.repo_ref)
            .await
            .map_err(UpdateLockError::NixPrefetchGit)?;

        if let Some(c) = current_commit {
            if c != fetch_output.rev {
                return Err(UpdateLockError::CommitMismatch(project.repo_ref.revision.clone()));
            }
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
    entries: BTreeMap<PathBuf, LockfileEntry>,
}

#[derive(Debug, Error)]
pub enum UpdateLockfileError {
    #[error("failed to update lock for `{project_path}`")]
    UpdateLock {
        #[source]
        error: UpdateLockError,
        project_path: PathBuf,
    },
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
    pub fn new(projects: &HashMap<PathBuf, Project>) -> Self {
        Lockfile {
            entries: projects
                .iter()
                .map(|(path, project)| (path.clone(), LockfileEntry {
                    project: project.clone(),
                    lock: None
                }))
                .collect(),
        }
    }

    pub fn set_projects(&mut self, new_projects: &HashMap<PathBuf, Project>) -> (u64, u64, u64) {
        let mut added = 0;
        let mut modified = 0;
        let mut removed = 0;

        for (_, project) in new_projects.iter() {
            match self.entries.get_mut(&project.path) {
                Some(ref mut entry) => {
                    if entry.project != *project {
                        if entry.project.repo_ref != project.repo_ref {
                            entry.lock = None;
                        }
                        entry.project = project.clone();
                        modified += 1;
                    }
                },
                None => {
                    self.entries.insert(project.path.clone(), LockfileEntry {
                        project: project.clone(),
                        lock: None
                    });
                    added += 1
                },
            }
        }

        let paths: Vec<_> = self.entries.keys().map(|x| x.clone()).collect();
        for path in paths {
            if !new_projects.iter().any(|(_, x)| x.path == path) {
                self.entries.remove(&path).unwrap();
                removed += 1;
            }
        }

        (added, modified, removed)
    }

    pub async fn read_from_file(path: &Path) -> Result<Self, ReadWriteLockfileError> {
        let json = fs::read(path).await.map_err(ReadWriteLockfileError::IO)?;
        serde_json::from_reader(json.as_slice()).map_err(ReadWriteLockfileError::Parse)
    }

    pub async fn write_to_file(&self, path: &Path) -> Result<(), ReadWriteLockfileError> {
        let json = serde_json::to_vec_pretty(self).map_err(ReadWriteLockfileError::Parse)?;
        fs::write(path, json.as_slice()).await.map_err(ReadWriteLockfileError::IO)
    }

    pub async fn update(&mut self, lockfile_path: Option<&Path>) -> Result<(), UpdateLockfileError> {
        let mut paths: Vec<_> = self.entries.keys().map(|x| x.clone()).collect();
        paths.sort();
        for (i, path) in paths.iter().enumerate() {
            {
                let entry = self.entries.get_mut(path).unwrap();
                eprintln!("Updating lock for `{}`... ({}/{})", path.display(), i, paths.len());
                entry.lock = Some(
                    update_lock(
                        &entry.project,
                        &entry.lock
                    )
                    .await
                    .map_err(|e| UpdateLockfileError::UpdateLock {
                        project_path: path.to_path_buf(),
                        error: e,
                    })?
                );
            }

            if let Some(p) = lockfile_path {
                self.write_to_file(p).await.map_err(UpdateLockfileError::WriteLockfile)?;
            }
        }
        Ok(())
    }
}
