use super::CommandLike;
use crate::prefetch_projects;
use anyhow::{Context, Result};
use clap::Parser;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestState};
use repo_types::{GitRef, GitRefOrCommitId, RepoUrl};
use std::fs::OpenOptions;
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};
use std::pin::Pin;

#[derive(Debug, Clone, Parser)]
pub struct Plain {
    manifest_url: String,

    #[arg(short = 'r', long = "ref")]
    manifest_repo_ref: String,

    #[arg(short = 'o', long = "output")]
    lockfile_path: PathBuf,
}

impl CommandLike for Plain {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        Box::pin(async move {
            let (_, _, fd) = handle
                .source_dir_by_ref_or_commit_id(
                    &RepoUrl(self.manifest_url.clone()),
                    &GitRefOrCommitId::GitRef(GitRef(self.manifest_repo_ref.clone())),
                )
                .await
                .context("failed to resolve ref of manifest repo")?;

            let instructions =
                repo_manifest::recursively_read_manifest(fd.as_fd(), Path::new("default.xml"))
                    .context("failed to recursively parse manifest files")?;

            let mut manifest_state = ManifestState::new(RepoUrl(self.manifest_url.clone()));
            for instruction in instructions {
                instruction
                    .execute_on(&mut manifest_state)
                    .context("failed to apply instruction to state")?;
            }

            let projects = prefetch_projects(&manifest_state, &handle)
                .await
                .context("failed to prefetch projects in manifest")?;

            let lockfile = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&self.lockfile_path)
                .context("failed to open lockfile for writing")?;
            serde_json::to_writer_pretty(lockfile, &projects)
                .context("failed to serialize projects to lockfile")?;

            Ok(())
        })
    }
}
