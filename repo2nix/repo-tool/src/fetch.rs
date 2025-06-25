use std::io;
use std::path::PathBuf;
use thiserror::Error;
use serde::Deserialize;
use serde_json;
use tokio::process::Command;

#[derive(Debug, Deserialize)]
pub struct NixPrefetchGitOutput {
    pub url: String,
    pub rev: String,
    pub date: u64,
    pub path: PathBuf,
    pub sha256: String,
    pub hash: String,
    #[serde(rename = "fetchLFS")]
    pub fetch_lfs: bool,
    #[serde(rename = "fetch_submodules")]
    pub fetch_submodules: bool,
    #[serde(rename = "deepClone")]
    pub deep_clone: bool,
    #[serde(rename = "leaveDotGit")]
    pub leave_dot_git: bool,
}

#[derive(Debug, Error)]
pub enum NixPrefetchGitError {
    #[error("couldn't spawn `nix-prefetch-git` process")]
    ProcessSpawn(#[from] io::Error),
    #[error("`nix-prefetch-git` did not return successfully ({0:?}), stderr:\n{1}")]
    NonzeroExitStatus(Option<i32>, String),
    #[error("couldn't parse `nix-prefetch-git` output")]
    Parse(#[from] serde_json::Error),
}

pub async fn nix_prefetch_git(url: &str, revision: &str, fetch_lfs: bool, fetch_submodules: bool) -> Result<NixPrefetchGitOutput, NixPrefetchGitError> {
    let mut flag_args = vec![];
    if fetch_lfs {
        flag_args.push("--fetch-lfs")
    }
    if fetch_submodules {
        flag_args.push("--fetch-submodules")
    }
    let output = Command::new("nix-prefetch-git")
        .arg("--url")
        .arg(url)
        .arg("--rev")
        .arg(revision)
        .args(&flag_args)
        .output()
        .await
        .map_err(NixPrefetchGitError::ProcessSpawn)?;

    if !output.status.success() {
        return Err(NixPrefetchGitError::NonzeroExitStatus(
                output.status.code(),
                String::from_utf8_lossy(&output.stderr).to_string()
        ));
    }

    serde_json::from_slice(&output.stdout)
        .map_err(NixPrefetchGitError::Parse)
}


#[derive(Debug, Error)]
pub enum GitLsRemoteError {
    #[error("couldn't spawn `git ls-remote` process")]
    ProcessSpawn(#[from] io::Error),
    #[error("`git ls-remote` did not return successfully ({0:?}), stderr:\n{1}")]
    NonzeroExitStatus(Option<i32>, String),
    #[error("error parsing `nix-prefetch-git-output` (shown below):\n{0}")]
    Parse(String),
    #[error("rev `{0}` not found at remote")]
    RevNotFound(String),
}

pub async fn git_ls_remote(url: &str, git_ref: &String) -> Result<String, GitLsRemoteError> {
    let output = Command::new("git")
        .arg("ls-remote")
        .arg(url)
        .output()
        .await
        .map_err(GitLsRemoteError::ProcessSpawn)?;

    if !output.status.success() {
        return Err(GitLsRemoteError::NonzeroExitStatus(
                output.status.code(),
                String::from_utf8_lossy(&output.stderr).to_string()
        ));
    }

    let output_str = String::from_utf8_lossy(&output.stdout);
    let mut revs = vec![];
    for line in output_str.split("\n") {
        if line != "" {
            let commit = line.split("\t").nth(0).ok_or(GitLsRemoteError::Parse(output_str.to_string()))?;
            let revname = line.split("\t").nth(1).ok_or(GitLsRemoteError::Parse(output_str.to_string()))?;
            revs.push((commit, revname));
        }
    }

    for (commit, revname) in revs {
        if revname == git_ref {
            return Ok(commit.to_string())
        }
    }

    Err(GitLsRemoteError::RevNotFound(git_ref.to_string()))
}

