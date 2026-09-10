use anyhow::{Context, Result, anyhow};
use crate::{Fetcher, FetchersHandle};
use crate::nix_prefetch_git::NixPrefetchGit;
use log::info;
use nix::errno::Errno;
use nix::fcntl::{OFlag, open};
use nix::sys::stat::Mode;
use nix_compat::derivation::{
    Derivation, DerivationError, Output, OutputHash, OutputHashMode, OutputName, Outputs,
};
use nix_compat::nixhash::NixHash;
use nix_compat::store_path::StorePath;
use repo_types::{ForgeSpecificRepoUrl, GitRefOrCommitId, RepoUrl};
use std::collections::{BTreeMap, BTreeSet};
use std::os::fd::OwnedFd;
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Default)]
pub struct SourceDirFd;

fn get_fod_path_of_nixhash(hash: &NixHash, name: &str) -> Result<StorePath, DerivationError> {
    let fod_hash = OutputHash {
        hash: hash.clone(),
        mode: OutputHashMode::Recursive,
    };
    let mut derivation = Derivation {
        arguments: vec![],
        builder: "".to_string(),
        environment: BTreeMap::new(),
        input_derivations: BTreeMap::new(),
        input_sources: BTreeSet::new(),
        outputs: Outputs::from_fod_hash(fod_hash),
        system: "".to_string(),
    };

    let hdm = derivation.hash_derivation_modulo(|_| panic!());
    derivation.calculate_output_paths(name, &hdm)?;

    Ok(derivation
        .outputs
        .get(&OutputName::out())
        .unwrap()
        .path
        .as_ref()
        .unwrap()
        .clone())
}

async fn open_path_if_exists(store_path: &Path) -> Result<Option<OwnedFd>, Errno> {
    // TODO(cyclic-pentane): this should be async, but I'm too lazy to figure out how to asyncify
    // that operation right now
    let fd = open(store_path, OFlag::O_RDONLY | OFlag::O_CLOEXEC, Mode::empty());
    match fd {
        Ok(fd) => Ok(Some(fd)),
        Err(Errno::ENOENT) => Ok(None),
        Err(e) => Err(e),
    }
}

impl Fetcher for SourceDirFd {
    type Args = (RepoUrl, git2::Oid, NixHash);
    type CacheKey = NixHash;
    type Output = Arc<OwnedFd>;

    async fn execute(
        &mut self,
        (repo_url, commit_hash, nix_hash): &Self::Args,
    ) -> Result<Arc<OwnedFd>> {
        let fs_repo_url = ForgeSpecificRepoUrl::from_repo_url(repo_url);
        info!("opening repo for reading: {:?}, commit {}", fs_repo_url, commit_hash);
        let name = fs_repo_url.derivation_name(commit_hash);
        let store_path = get_fod_path_of_nixhash(nix_hash, &name)
            .context("failed to calculate FOD path of nix hash")?
            .to_absolute_path();
        let store_path = PathBuf::from(store_path);
        let fd = open_path_if_exists(&store_path)
            .await
            .context("failed to open store path")?;
        let fd = match fd {
            Some(fd) => fd,
            None => {
                // apparently we got the hash from the lockfile, and the nix garbage collector ran
                // in the meanwhile (or the lockfile was generated on another host). Let's attempt
                // to refetch.
                let new_nix_hash = NixPrefetchGit::default()
                    .execute(&(repo_url.clone(), commit_hash.clone()))
                    .await
                    .context("failed to re-fetch store path")?;
                if new_nix_hash != *nix_hash {
                    return Err(anyhow!(
                        "the content hash of newly fetched store path doesn't match our stored hash. This means that something is very wrong - either the `git` process of `nix-prefetch-git` is buggy and didn't properly check the hash of the commit it downloaded, or the HTTP API of the forge returned a tarball with a content hash that's different from last time."
                    ));
                }
                // now, hopefully, we have it?
                open_path_if_exists(&store_path)
                    .await
                    .context("failed to open store path")?
                    .ok_or(anyhow!(
                        "store path {} still isn't there after re-invoking the prefetcher",
                        store_path.display()
                    ))?
            }
        };

        Ok(Arc::new(fd))
    }

    fn cache_key((_, _, content_hash): &Self::Args) -> Self::CacheKey {
        content_hash.clone()
    }
}

impl FetchersHandle {
    pub async fn source_dir_by_ref_or_commit_id(&self, repo_url: &RepoUrl, git_ref_or_commit_id: &GitRefOrCommitId) -> Result<(git2::Oid, NixHash, Arc<OwnedFd>)> {
        let (commit_id, nix_hash) = self
            .prefetch_by_ref_or_commit_id(repo_url, git_ref_or_commit_id)
            .await
            .context("failed to prefetch repo by GitRefOrCommitId")?;

        let fd = self
            .source_dir_fd(
                &(
                    repo_url.clone(),
                    commit_id.clone(),
                    nix_hash.clone(),
                )
            )
            .await
            .context("failed to open source dir fd")?;

        Ok((commit_id, nix_hash, fd))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fod_path() {
        let hash =
            NixHash::from_sri("sha256-jE4pLqNB9Ds2vcIGnt0XbTMwWwJgskqtDaYuMjWUDeA=").unwrap();
        let fod_path = get_fod_path_of_nixhash(&hash, "manifest-ad156f3").unwrap();
        assert_eq!(
            fod_path,
            StorePath::from_absolute_path(
                "/nix/store/64rjg2vwc7wzg4468cc3x66b9hnb6gjp-manifest-ad156f3".as_bytes()
            )
            .unwrap(),
        );
    }
}
