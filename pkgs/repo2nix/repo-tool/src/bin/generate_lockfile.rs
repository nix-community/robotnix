use anyhow::{Context, Result};
use clap::Parser;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestState};
use repo_tool::{CommonCliArgs, prefetch_projects};
use repo_types::{GitRef, GitRefOrCommitId, RepoUrl};
use std::fs::OpenOptions;
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};
use tokio::select;

#[derive(Parser)]
struct CliArgs {
    #[command(flatten)]
    common: CommonCliArgs,

    manifest_url: String,

    #[arg(short = 'r', long = "ref")]
    manifest_repo_ref: String,

    #[arg(short = 'o', long = "output")]
    lockfile_path: PathBuf,
}

async fn run(args: CliArgs, handle: FetchersHandle) -> Result<()> {
    let (_, _, fd) = handle
        .source_dir_by_ref_or_commit_id(
            &RepoUrl(args.manifest_url.clone()),
            &GitRefOrCommitId::GitRef(GitRef(args.manifest_repo_ref.clone())),
        )
        .await
        .context("failed to resolve ref of manifest repo")?;

    let instructions =
        repo_manifest::recursively_read_manifest(fd.as_fd(), Path::new("default.xml"))
            .context("failed to recursively parse manifest files")?;

    let mut manifest_state = ManifestState::new(RepoUrl(args.manifest_url.clone()));
    for instruction in instructions {
        instruction.execute_on(&mut manifest_state)
            .context("failed to apply instruction to state")?;
    }

    let projects = prefetch_projects(&manifest_state, &handle)
        .await
        .context("failed to prefetch projects in manifest")?;

    let lockfile = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&args.lockfile_path)
        .context("failed to open lockfile for writing")?;
    serde_json::to_writer_pretty(lockfile, &projects)
        .context("failed to serialize projects to lockfile")?;

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = CliArgs::parse();
    stderrlog::new()
        .verbosity(args.common.verbosity)
        .show_module_names(true)
        .init()
        .context("failed to initialize stderrlog")?;

    let (handle, mut worker_jhs) = FetchersHandle::spawn_workers(
        args.common.nixhash_lockfile.as_ref().map(|x| x.as_ref()),
        args.common.fetcher_tasks,
    )
        .await
        .context("failed to spawn fetcher tasks")
        .unwrap();

    select![
        r = run(args, handle) => r?,
        r = worker_jhs.join_next() => r.context("failed to join worker tasks")???,
    ];

    Ok(())
}
