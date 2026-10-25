use anyhow::{Context, Result};
use crate::prefetch_project_by_relpath;
use nix::fcntl::{openat, OFlag};
use nix::sys::stat::Mode;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::ManifestState;
use std::fs::File;
use std::io::{BufRead, BufReader};

pub async fn get_aosp_build_id(manifest: &ManifestState, handle: &FetchersHandle) -> Result<String> {
    let (repo_url, commit_id, nix_hash) = prefetch_project_by_relpath(manifest, "build/make", handle)
        .await
        .context("failed to prefetch build/make repo")?;
    let repo_fd = handle
        .source_dir_fd(&(repo_url, commit_id, nix_hash))
        .await
        .context("failed to open build/make repo for reading")?;

    let build_id_mk_fd = openat(
        repo_fd,
        "core/build_id.mk",
        OFlag::O_RDONLY | OFlag::O_CLOEXEC,
        Mode::empty(),
    )
        .context("failed to open core/build_id.mk file")?;

    let file = File::from(build_id_mk_fd);
    let file = BufReader::new(file);
    let mut build_id = None;
    for line in file.lines() {
        let line = line.context("failed to read line from file")?;
        let line = line.trim();
        if let Some(build_id_str) = line.strip_prefix("BUILD_ID=") {
            build_id = Some(build_id_str.to_string());
            break;
        }
    }

    Ok(build_id.context("core/build_id.mk doesn't contain line starting with `BUILD_ID=`")?)
}
