use serde::Deserialize;
use serde_json;
use std::io;
use std::path::PathBuf;
use thiserror::Error;
use tokio::process::Command;
use url::Url;

#[derive(Debug, Deserialize)]
pub struct NixPrefetchGitOutput {
    #[allow(dead_code)]
    pub url: String,

    pub rev: String,

    pub date: u64,

    pub path: PathBuf,

    #[allow(dead_code)]
    pub sha256: String,

    pub hash: String,

    #[allow(dead_code)]
    #[serde(rename = "fetchLFS")]
    pub fetch_lfs: bool,

    #[allow(dead_code)]
    #[serde(rename = "fetchSubmodules")]
    pub fetch_submodules: bool,

    #[allow(dead_code)]
    #[serde(rename = "deepClone")]
    pub deep_clone: bool,

    #[allow(dead_code)]
    #[serde(rename = "leaveDotGit")]
    pub leave_dot_git: bool,
}

#[derive(Debug, Error)]
pub enum NixPrefetchGitError {
    #[error("couldn't spawn `{0}` process")]
    ProcessSpawn(String, #[source] io::Error),
    #[error("`{0}` did not return successfully ({1:?}), stderr:\n{2}")]
    NonzeroExitStatus(String, Option<i32>, String),
    #[error("couldn't parse `nix-prefetch-git` output")]
    Parse(#[from] serde_json::Error),
}

pub async fn nix_prefetch_git(
    repo_url: &Url,
    revision: &str,
    fetch_lfs: bool,
    fetch_submodules: bool,
    cleanup: bool,
) -> Result<NixPrefetchGitOutput, NixPrefetchGitError> {
    eprintln!("Prefetching `{}`, revision {}...", repo_url, revision);
    let mut flag_args = vec![];
    if fetch_lfs {
        flag_args.push("--fetch-lfs")
    }
    if fetch_submodules {
        flag_args.push("--fetch-submodules")
    }
    let output = Command::new("nix-prefetch-git")
        .arg("--url")
        .arg(repo_url.as_str())
        .arg("--rev")
        .arg(&revision)
        .args(&flag_args)
        .output()
        .await
        .map_err(|e| NixPrefetchGitError::ProcessSpawn("nix-prefetch-git".to_string(), e))?;

    if !output.status.success() {
        return Err(NixPrefetchGitError::NonzeroExitStatus(
            "nix-prefetch-git".to_string(),
            output.status.code(),
            String::from_utf8_lossy(&output.stderr).to_string(),
        ));
    }

    let output: NixPrefetchGitOutput = serde_json::from_slice(&output.stdout)?;

    if cleanup {
        let output = Command::new("nix-store")
            .arg("--delete")
            .arg(&output.path)
            .output()
            .await
            .map_err(|e| NixPrefetchGitError::ProcessSpawn("nix-store".to_string(), e))?;

        if !output.status.success() {
            return Err(NixPrefetchGitError::NonzeroExitStatus(
                "nix-store".to_string(),
                output.status.code(),
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }
    }

    Ok(output)
}

#[derive(Debug, Error)]
pub enum GitLsRemoteError {
    #[error("couldn't spawn `git ls-remote` process")]
    ProcessSpawn(#[from] io::Error),
    #[error("`git ls-remote` did not return successfully ({0:?}), stderr:\n{1}")]
    NonzeroExitStatus(Option<i32>, String),
    #[error("`git ls-remote` returned invalid UTF-8")]
    Utf8(std::str::Utf8Error),
    #[error("rev not found at remote")]
    RevNotFound,
    #[error("error parsing output")]
    Parse,
}

pub async fn git_ls_remote(url: &str, git_ref: &str) -> Result<String, GitLsRemoteError> {
    let output = Command::new("git")
        .arg("ls-remote")
        .arg(url)
        .output()
        .await?;

    if !output.status.success() {
        return Err(GitLsRemoteError::NonzeroExitStatus(
            output.status.code(),
            String::from_utf8_lossy(&output.stderr).to_string(),
        ));
    }

    let output_str = std::str::from_utf8(&output.stdout).map_err(GitLsRemoteError::Utf8)?;
    for line in output_str.split("\n") {
        if line.ends_with(git_ref) {
            let commit = line.split("\t").next().unwrap();
            return Ok(commit.to_string());
        }
    }

    Err(GitLsRemoteError::RevNotFound)
}
