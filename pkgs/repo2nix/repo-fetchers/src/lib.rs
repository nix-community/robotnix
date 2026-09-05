use anyhow::{Context, Result, anyhow};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::path::PathBuf;
use tokio::sync::oneshot::{Sender, channel};

pub mod get_repo_refs;
pub mod http_get;
pub mod nix_prefetch_git;
pub mod source_dir_fd;

pub mod spawn;

use get_repo_refs::GetRepoRefs;
use http_get::HttpGet;
use nix_prefetch_git::NixPrefetchGit;
use source_dir_fd::SourceDirFd;

pub trait Fetcher: Default {
    type Args: 'static + Send + Clone;
    type CacheKey: 'static + Ord;
    type Output: 'static + Send + Clone;

    fn execute(&mut self, args: &Self::Args) -> impl Future<Output = Result<Self::Output>>;

    fn cache_key(args: &Self::Args) -> Self::CacheKey;
}

pub enum CachingState<F: Fetcher> {
    EnqueuedOrRunning(Vec<Sender<F::Output>>),
    Cached(F::Output),
}

pub struct FetcherCache<F: Fetcher>(BTreeMap<F::CacheKey, CachingState<F>>);

impl<F: Fetcher> FetcherCache<F> {
    pub fn empty() -> Self {
        Self(BTreeMap::new())
    }

    pub fn enqueue(&mut self, args: &F::Args, sender: Sender<F::Output>) -> Result<bool> {
        let (needs_insertion, senders) = match self.0.get_mut(&F::cache_key(args)) {
            Some(CachingState::EnqueuedOrRunning(senders)) => {
                senders.push(sender);
                (false, vec![])
            }
            Some(CachingState::Cached(output)) => {
                sender
                    .send(output.clone())
                    .map_err(|_| anyhow!("failed to send output to oneshot channel"))?;
                (false, vec![])
            }
            None => (true, vec![sender]),
        };

        if needs_insertion {
            self.0
                .insert(F::cache_key(args), CachingState::EnqueuedOrRunning(senders));
        }

        Ok(needs_insertion)
    }

    pub fn finalize(&mut self, args: F::Args, output: F::Output) -> Result<()> {
        let state = self.0.remove(&F::cache_key(&args));
        match state {
            Some(CachingState::EnqueuedOrRunning(senders)) => {
                for sender in senders {
                    sender
                        .send(output.clone())
                        .map_err(|_| anyhow!("failed to send output to oneshot channel"))?;
                }
            }
            Some(CachingState::Cached(_)) | None => {
                panic!("invalid caching state for provided args")
            }
        }

        self.0
            .insert(F::cache_key(&args), CachingState::Cached(output));

        Ok(())
    }
}

// The "obvious" refactor to use dynamic dispatch or enum_dispatch doesn't work for two reasons:
// - The fetcher threads can have request-variant-specific runtimes (such as reqwest::Client for
// HttpGet connection pooling)
// - The return types are request-variant specific too.
// - We need
//
// Handling this properly would require Rust to have fancier metaprogramming features, such as for
// loops that can iterate over all fields of a struct (and within whose function bodies only trait
// methods common to all struct field types can be called). Still, I deliberately structured the
// code in this crate in a way to make the underlying structure we can't (yet?) express in Rust
// as in-your-face as possible.

#[derive(Default)]
pub struct Fetchers {
    http_get: HttpGet,
    get_repo_refs: GetRepoRefs,
    nix_prefetch_git: NixPrefetchGit,
    source_dir_fd: SourceDirFd,
}

pub struct FetcherCaches {
    http_get: FetcherCache<HttpGet>,
    get_repo_refs: FetcherCache<GetRepoRefs>,
    nix_prefetch_git: FetcherCache<NixPrefetchGit>,
    source_dir_fd: FetcherCache<SourceDirFd>,
}

enum FetchRequest {
    HttpGet(
        <HttpGet as Fetcher>::Args,
        Sender<<HttpGet as Fetcher>::Output>,
    ),
    GetRepoRefs(
        <GetRepoRefs as Fetcher>::Args,
        Sender<<GetRepoRefs as Fetcher>::Output>,
    ),
    NixPrefetchGit(
        <NixPrefetchGit as Fetcher>::Args,
        Sender<<NixPrefetchGit as Fetcher>::Output>,
    ),
    SourceDirFd(
        <SourceDirFd as Fetcher>::Args,
        Sender<<SourceDirFd as Fetcher>::Output>,
    ),
}

enum FetchCommand {
    HttpGet(<HttpGet as Fetcher>::Args),
    GetRepoRefs(<GetRepoRefs as Fetcher>::Args),
    NixPrefetchGit(<NixPrefetchGit as Fetcher>::Args),
    SourceDirFd(<SourceDirFd as Fetcher>::Args),
}

pub struct GlobalConfig {
    nixhash_lockfile: Option<PathBuf>,
}

struct FetchersState {
    queue: VecDeque<FetchCommand>,
    caches: FetcherCaches,
    global_config: GlobalConfig,
}

impl FetchersState {
    fn insert_request(&mut self, request: FetchRequest) -> Result<()> {
        match request {
            FetchRequest::HttpGet(args, sender) => {
                if self.caches.http_get.enqueue(&args, sender)? {
                    self.queue.push_back(FetchCommand::HttpGet(args))
                }
            }
            FetchRequest::GetRepoRefs(args, sender) => {
                if self.caches.get_repo_refs.enqueue(&args, sender)? {
                    self.queue.push_back(FetchCommand::GetRepoRefs(args))
                }
            }
            FetchRequest::NixPrefetchGit(args, sender) => {
                if self.caches.nix_prefetch_git.enqueue(&args, sender)? {
                    self.queue.push_back(FetchCommand::NixPrefetchGit(args))
                }
            }
            FetchRequest::SourceDirFd(args, sender) => {
                if self.caches.source_dir_fd.enqueue(&args, sender)? {
                    self.queue.push_back(FetchCommand::SourceDirFd(args))
                }
            }
        };
        Ok(())
    }

    async fn run_worker(self_mutex: Arc<Mutex<Self>>) -> Result<()> {
        let mut fetchers = Fetchers::default();

        loop {
            let next_command = {
                let next_command = {
                    let mut lock = self_mutex
                        .lock()
                        .map_err(|_| anyhow!("failed to lock Self mutex"))?;
                    lock.queue.pop_front()
                };
                let Some(next_command) = next_command else {
                    // TODO better mechanism
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                    continue;
                };
                next_command
            };

            match next_command {
                FetchCommand::HttpGet(args) => {
                    let out = fetchers
                        .http_get
                        .execute(&args)
                        .await
                        .context("failed to execute http_get fetcher")?;
                    self_mutex
                        .lock()
                        .map_err(|_| anyhow!("failed to lock Self mutex"))?
                        .caches
                        .http_get
                        .finalize(args, out)
                        .context("failed to insert fetcher output into cache")?;
                },
                FetchCommand::GetRepoRefs(args) => {
                    let out = fetchers
                        .get_repo_refs
                        .execute(&args)
                        .await
                        .context("failed to execute get_repo_refs fetcher")?;
                    self_mutex
                        .lock()
                        .map_err(|_| anyhow!("failed to lock Self mutex"))?
                        .caches
                        .get_repo_refs
                        .finalize(args, out)
                        .context("failed to insert fetcher output into cache")?;
                },
                FetchCommand::NixPrefetchGit(args) => {
                    let out = fetchers
                        .nix_prefetch_git
                        .execute(&args)
                        .await
                        .context("failed to execute nix_prefetch_git fetcher")?;
                    {
                        let mut self_locked = self_mutex
                            .lock()
                            .map_err(|_| anyhow!("failed to lock Self mutex"))?;

                        self_locked
                            .caches
                            .nix_prefetch_git
                            .finalize(args, out)
                            .context("failed to insert fetcher output into cache")?;

                        if let Some(ref nixhash_lockfile) = self_locked.global_config.nixhash_lockfile {
                            self_locked
                                .caches
                                .save(nixhash_lockfile)
                                .context("failed to save cache state to disk")?;
                        }
                    }
                },
                FetchCommand::SourceDirFd(args) => {
                    let out = fetchers
                        .source_dir_fd
                        .execute(&args)
                        .await
                        .context("failed to execute source_dir_fd fetcher")?;
                    self_mutex
                        .lock()
                        .map_err(|_| anyhow!("failed to lock Self mutex"))?
                        .caches
                        .source_dir_fd
                        .finalize(args, out)
                        .context("failed to insert fetcher output into cache")?;
                },
            }
        }
    }
}

#[derive(Clone)]
pub struct FetchersHandle(Arc<Mutex<FetchersState>>);

impl FetchersHandle {
    async fn http_get(
        &self,
        args: &<HttpGet as Fetcher>::Args,
    ) -> Result<<HttpGet as Fetcher>::Output> {
        let (tx, rx) = channel();
        self.0
            .lock()
            .map_err(|_| anyhow!("failed to lock mutex"))?
            .insert_request(FetchRequest::HttpGet(args.clone(), tx))
            .context("failed to insert request")?;
        rx.await.map_err(|_| anyhow!("channel closed"))
    }

    async fn get_repo_refs(
        &self,
        args: &<GetRepoRefs as Fetcher>::Args,
    ) -> Result<<GetRepoRefs as Fetcher>::Output> {
        let (tx, rx) = channel();
        self.0
            .lock()
            .map_err(|_| anyhow!("failed to lock mutex"))?
            .insert_request(FetchRequest::GetRepoRefs(args.clone(), tx))
            .context("failed to insert request")?;
        rx.await.map_err(|_| anyhow!("channel closed"))
    }

    async fn nix_prefetch_git(
        &self,
        args: &<NixPrefetchGit as Fetcher>::Args,
    ) -> Result<<NixPrefetchGit as Fetcher>::Output> {
        let (tx, rx) = channel();
        self.0
            .lock()
            .map_err(|_| anyhow!("failed to lock mutex"))?
            .insert_request(FetchRequest::NixPrefetchGit(args.clone(), tx))
            .context("failed to insert request")?;
        rx.await.map_err(|_| anyhow!("channel closed"))
    }

    async fn source_dir_fd(
        &self,
        args: &<SourceDirFd as Fetcher>::Args,
    ) -> Result<<SourceDirFd as Fetcher>::Output> {
        let (tx, rx) = channel();
        self.0
            .lock()
            .map_err(|_| anyhow!("failed to lock mutex"))?
            .insert_request(FetchRequest::SourceDirFd(args.clone(), tx))
            .context("failed to insert request")?;
        rx.await.map_err(|_| anyhow!("channel closed"))
    }
}
