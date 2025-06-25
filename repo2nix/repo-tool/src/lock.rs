use thiserror::Error;
use repo_manifest::resolver::{
    Project,
};
use crate::fetch::{
    nix_prefetch_git,
    git_ls_remote,
    NixPrefetchGitError,
    GitLsRemoteError,
};

#[derive(Debug, Clone)]
pub struct Lock {
    // TODO proper [u8, 20] type for commit with (de)?serializer
    pub commit: String,
    pub nix_hash: String,
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
        let fetch_output = nix_prefetch_git(project.repo_ref.repo_url.as_str(), &project.repo_ref.revision, true, false)
            .await
            .map_err(UpdateLockError::NixPrefetchGit)?;

        if let Some(c) = current_commit {
            if c != fetch_output.rev {
                return Err(UpdateLockError::CommitMismatch(project.repo_ref.revision.clone()));
            }
        }

        Ok(Lock {
            commit: fetch_output.rev.clone(),
            nix_hash: fetch_output.hash,
        })
    } else {
        Ok(lock.clone().unwrap())
    }
}
