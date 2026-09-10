use anyhow::{Context, Result};
use clap::Parser;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestState};
use repo_tool::{CliArgs, prefetch_projects};
use repo_tool::commands::CommandLike;
use repo_types::{GitRef, GitRefOrCommitId, RepoUrl};
use std::fs::OpenOptions;
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};
use tokio::select;

#[tokio::main]
async fn main() -> Result<()> {
    let args = CliArgs::parse();
    stderrlog::new()
        .verbosity(args.verbosity)
        .show_module_names(true)
        .init()
        .context("failed to initialize stderrlog")?;

    let (handle, mut worker_jhs) = FetchersHandle::spawn_workers(
        args.nixhash_lockfile.as_ref().map(|x| x.as_ref()),
        args.fetcher_tasks,
    )
        .await
        .context("failed to spawn fetcher tasks")
        .unwrap();

    select![
        r = args.command.run(handle) => r?,
        r = worker_jhs.join_next() => r.context("failed to join worker tasks")???,
    ];

    Ok(())
}
