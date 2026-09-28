use anyhow::{Context, Result};
use clap::Parser;
use crate::commands::{self, CommandLike};
use log::info;
use repo_fetchers::FetchersHandle;
use std::path::PathBuf;
use std::pin::Pin;

#[derive(Clone, Debug, Parser)]
pub struct LineageOSBranches {
    #[arg(short, long = "branch")]
    branches: Vec<String>,

    #[arg(short = 'o', long = "out-dir")]
    lockfiles_dir: PathBuf,
}

impl CommandLike for LineageOSBranches {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        Box::pin(async move {
            for branch in self.branches {
                info!("Generating lockfile for branch {branch}");
                (commands::lineageos::LineageOS {
                    lockfile_path: self.lockfiles_dir.join(&branch).with_added_extension("lock"),
                    branch,
                }).run(handle.clone()).await?
            }

            Ok(())
        })
    }
}
