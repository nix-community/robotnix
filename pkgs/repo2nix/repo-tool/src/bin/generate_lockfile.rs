use anyhow::{Context, Result};
use clap::Parser;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestState};
use repo_tool::{CommonCliArgs, prefetch_projects};
use repo_types::{GitRef, GitRefOrCommitId, RepoUrl};
use std::os::fd::AsFd;
use std::path::Path;
use tokio::select;

#[derive(Parser)]
struct CliArgs {
    #[command(flatten)]
    common: CommonCliArgs,

    manifest_url: String,

    #[arg(short = 'r', long = "ref")]
    manifest_repo_ref: String,
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

    let manifest_state = ManifestState::new(RepoUrl(args.manifest_url.clone()));
    let manifest_state = instructions.into_iter().fold(
        Ok::<_, anyhow::Error>(manifest_state),
        |state, instruction| {
            let mut state = state?;
            instruction
                .execute_on(&mut state)
                .context("failed to execute manifest instruction on state")?;
            Ok(state)
        },
    )
        .context("failed to apply manifest instructions")?;
    let projects = prefetch_projects(&manifest_state, &handle)
        .await
        .context("failed to prefetch projects in manifest")?;

    println!("{projects:#?}");
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
