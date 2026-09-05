use anyhow::{Context, Result};
use crate::{
    CachingState,
    FetcherCache,
    FetcherCaches,
    FetchersState,
    FetchersHandle,
    GlobalConfig,
};
use nix_compat::nixhash::NixHash;
use std::collections::BTreeMap;
use std::collections::VecDeque;
use std::fs::{File, OpenOptions};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::io::AsyncReadExt;
use tokio::task::JoinSet;

impl FetcherCaches {
    pub fn load(nixhash_lockfile: Option<&Path>) -> Result<FetcherCaches> {
        let cache = FetcherCaches {
            http_get: FetcherCache::empty(),
            get_repo_refs: FetcherCache::empty(),
            nix_prefetch_git: match nixhash_lockfile {
                Some(nixhash_lockfile) => match File::open(nixhash_lockfile) {
                    Ok(file) => {
                        let hashes: BTreeMap<String, String> = serde_json::from_reader(file)
                            .context("failed to deserialize nixhash lockfile")?;

                        let hashes: BTreeMap<git2::Oid, NixHash> = hashes
                            .iter()
                            .map(|(commit_id, nix_hash)| {
                                Ok::<_, anyhow::Error>(
                                    (
                                        git2::Oid::from_str(commit_id)
                                            .context("failed to parse commit ID")?,
                                        NixHash::from_sri(nix_hash)
                                            .context("failed to parse Nix SRI hash")?,
                                    )
                                )
                            })
                            .collect::<Result<BTreeMap<_, _>, _>>()?;
                        
                        FetcherCache(
                            hashes
                                .into_iter()
                                .map(|(commit_id, nix_hash)| (commit_id, CachingState::Cached(nix_hash)))
                                .collect()
                        )
                    },
                    Err(e) if e.kind() == ErrorKind::NotFound => FetcherCache::empty(),
                    Err(e) => return Err(e).context("failed to open nixhash lockfile"),
                },
                None => FetcherCache::empty(),
            },
            source_dir_fd: FetcherCache::empty(),
        };

        Ok(cache)
    }

    pub fn save(&self, nixhash_lockfile: &Path) -> Result<()> {
        let hashes = self
            .nix_prefetch_git
            .0
            .iter()
            .filter_map(|(commit_id, state)| match state {
                CachingState::Cached(nix_hash) => Some((commit_id.to_string(), nix_hash.to_sri_string())),
                _ => None,
            })
            .collect::<BTreeMap<_, _>>();
        let file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(nixhash_lockfile)
            .context("failed to open nixhash lockfile for writing")?;

        serde_json::to_writer_pretty(
            file,
            &hashes,
        )
            .context("failed to serialize nixhash lockfile")
    }
}

impl FetchersHandle {
    pub async fn new(nixhash_lockfile: Option<&Path>) -> Result<Self> {
        Ok(Self(Arc::new(Mutex::new(FetchersState {
            queue: VecDeque::new(),
            caches:
                FetcherCaches::load(nixhash_lockfile)
                .context("failed to load fetcher caches")?,
            global_config: GlobalConfig {
                nixhash_lockfile: nixhash_lockfile.map(PathBuf::from),
            },
        }))))
    }

    pub async fn spawn_workers(
        nixhash_lockfile: Option<&Path>,
        n_workers: u64,
    ) -> Result<(FetchersHandle, JoinSet<Result<()>>)> {
        let handle = Self::new(nixhash_lockfile)
            .await
            .context("failed to instantiate new FetchersState")?;

        let mut join_set = JoinSet::new();
        for _ in 0..n_workers {
            let handle = handle.clone();
            join_set.spawn(FetchersState::run_worker(handle.0));
        }

        Ok(
            (
                handle,
                join_set,
            )
        )
    }
}
