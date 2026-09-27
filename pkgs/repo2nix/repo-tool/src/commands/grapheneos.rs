use anyhow::{Context, Result};
use clap::Parser;
use crate::prefetch_projects;
use nix_compat::nixhash::NixHash;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestState};
use repo_types::{DeviceName, GitRef, GitRefOrCommitId, RepoUrl, lockfile};
use serde::{Serialize, Deserialize};
use std::collections::BTreeMap;
use std::fs::OpenOptions;
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use super::CommandLike;


#[derive(Serialize, Deserialize)]
struct VendorImage {
    #[serde(rename = "fileName")]
    filename: String,
    url: String,
    #[serde(rename = "sha256")]
    hash: String,
}

#[derive(Debug, Clone, Parser)]
pub struct GrapheneOS {
    #[arg(short, long)]
    tag: String,

    #[arg(short = 'o', long = "output")]
    lockfile_path: PathBuf,
}

impl CommandLike for GrapheneOS {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        Box::pin(async move {
            let manifest_url = RepoUrl("https://github.com/GrapheneOS/platform_manifest".to_string());
            let (_, _, manifest_fd) = handle
                .source_dir_by_ref_or_commit_id(
                    &manifest_url,
                    &GitRefOrCommitId::GitRef(GitRef(format!("refs/tags/{}", self.tag))),
                )
                .await
                .context("failed to fetch manifest repo")?;

            let instructions =
                repo_manifest::recursively_read_manifest(manifest_fd.as_fd(), Path::new("default.xml"))
                .context("failed to recursively read manifest")?;

            let mut manifest = ManifestState::new(manifest_url.clone());
            for instruction in instructions {
                instruction
                    .execute_on(&mut manifest)
                    .context("failed to apply instruction to manifest")?;
            }

            let projects = prefetch_projects(&manifest, &handle)
                .await
                .context("failed to prefetch projects")?;

            #[derive(Serialize)]
            struct GrapheneLockfile {
                projects: BTreeMap<PathBuf, lockfile::Project>,
                #[serde(with = "repo_types::custom_serde::nix_hash")]
                adevtool_yarn_hash: NixHash,
                vendor_images: BTreeMap<DeviceName, Vec<VendorImage>>,
            }

            let lockfile = GrapheneLockfile {
                projects,
                adevtool_yarn_hash: todo!(),
                vendor_images: todo!(),
            };

            let file = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&self.lockfile_path)
                .context("failed to open lockfile for writing")?;

            serde_json::to_writer_pretty(file, &lockfile)
                .context("failed to serialize lockfile")?;

            Ok(())
        })
    }
}
