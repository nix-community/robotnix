use anyhow::{Context, Result, anyhow};
use crate::{Fetcher, FetchersHandle};
use log::{info, warn, error};
use nix_compat::nixhash::NixHash;
use repo_types::{ForgeSpecificRepoUrl, GitRefOrCommitId, RepoUrl, FetchUrl};
use serde::Deserialize;
use std::path::Path;
use std::time::Duration;
use tokio::process::Command;

#[derive(Default)]
pub struct NixPrefetchGit;

async fn check_mirror_repo_for_commit(mirror_repo_path: &Path, commit_id: &git2::Oid) -> Result<bool> {
    let out = Command::new("git")
        .arg("-C")
        .arg(&mirror_repo_path)
        .arg("show")
        .arg(&commit_id.to_string())
        .output()
        .await
        .context("failed to run git show process")?;

    if out.status.success() {
        Ok(true)
    } else {
        if out.status.code() == Some(128) && out.stderr == format!("fatal: bad object {}\n", commit_id).as_bytes() {
            Ok(false)
        } else {
            Err(anyhow!("git show failed with stderr: {}", String::from_utf8_lossy(&out.stderr[..])))
        }
    }
}

async fn maybe_prepare_mirror(repo_url: &RepoUrl, commit_id: &git2::Oid) -> Result<FetchUrl> {
    let fs_repo_url = ForgeSpecificRepoUrl::from_repo_url(repo_url);
    let mirror_dir = std::env::var_os("ROBOTNIX_GIT_MIRROR_DIR");
    match mirror_dir {
        None => Ok(fs_repo_url.to_fetch_url(commit_id)),
        Some(mirror_dir) => {
            let mirror_dir = Path::new(&mirror_dir)
                .canonicalize()
                .context("failed to canonicalize mirror dir path")?;
            let mirror_repo_path = Path::new(&mirror_dir)
                .join(fs_repo_url.mirror_path());
            if tokio::fs::try_exists(&mirror_repo_path).await.context("failed to check whether mirror repo exists on disk")? {
                if check_mirror_repo_for_commit(&mirror_repo_path, commit_id).await? == false {
                    info!("{} doesn't seem to have commit {} yet, fetching from default remote...", mirror_repo_path.display(), commit_id);
                    let out = Command::new("git")
                        .arg("-C")
                        .arg(&mirror_repo_path)
                        .arg("fetch")
                        .output()
                        .await
                        .context("failed to run git fetch process")?;

                    if !out.status.success() {
                        return Err(anyhow!("git fetch failed with stderr: {}", String::from_utf8_lossy(&out.stderr[..])));
                    }
                }
            } else {
                warn!("mirror repo {} doesn't exist yet, cloning...", mirror_repo_path.display());
                let mut retries = 0;
                loop {
                    let out = Command::new("git")
                        .arg("clone")
                        .arg("--bare")
                        .arg(&repo_url.0)
                        .arg(&mirror_repo_path)
                        .output()
                        .await
                        .context("failed to run git clone process")?;
                    if !out.status.success() {
                        let stderr = String::from_utf8_lossy(&out.stderr[..]);
                        if retries >= 10 {
                            return Err(anyhow!("git clone failed after 10 retries with stderr: {}", stderr));
                        }
                        error!("git clone failed with stderr: {}", stderr);
                        tokio::time::sleep(Duration::from_secs(1) * 2_u32.pow(retries)).await;
                        retries += 1;
                    } else {
                        break;
                    }
                }
            }
            Ok(FetchUrl::GitRemote {
                repo_url: RepoUrl(mirror_repo_path.to_str().context("mirror repo path contains invalid utf8")?.to_string()),
                commit_id: *commit_id
            })
        },
    }
}

impl Fetcher for NixPrefetchGit {
    type Args = (RepoUrl, git2::Oid);
    // gratuitiously assuming no SHA1 collisions, lmao
    // also, we're assuming that the tree tarballs served by the forges do indeed correspond to the
    // commit hashes - to verify this, we'd have to download the tarball, hash it git style,
    // download the commit metadata, hash that too, and then compare the calculated commit hash to the expected
    // one, but i don't think it's worth the overhead
    // TODO(cyclic-pentane) think about the security implications of this
    type CacheKey = git2::Oid;
    type Output = NixHash;

    async fn execute(&mut self, (repo_url, commit_id): &Self::Args) -> Result<NixHash> {
        info!("prefetching repo {:?}, commit {}", repo_url, commit_id);
        let fs_repo_url = ForgeSpecificRepoUrl::from_repo_url(repo_url);
        let derivation_name = fs_repo_url.derivation_name(commit_id);
        let fetch_url = maybe_prepare_mirror(repo_url, commit_id)
            .await
            .context("failed to prepare local mirror repo")?;
        let hash = match fetch_url {
            FetchUrl::GitRemote {
                repo_url,
                commit_id,
            } => {
                let out = Command::new("nix-prefetch-git")
                    .arg("--fetch-lfs")
                    .arg("--name")
                    .arg(&derivation_name)
                    .arg("--rev")
                    .arg(&commit_id.to_string())
                    .arg("--url")
                    .arg(&repo_url.0)
                    .output()
                    .await
                    .context("failed to run nix-prefetch-git process")?;
                if !out.status.success() {
                    return Err(anyhow!(
                        "process failed with stderr:\n{}",
                        String::from_utf8_lossy(&out.stderr[..])
                    ));
                }

                #[derive(Deserialize)]
                struct NixPrefetchGitOutput {
                    sha256: String,
                }

                let out: NixPrefetchGitOutput = serde_json::from_slice(&out.stdout[..])
                    .context("failed to deserialize nix-prefetch-git output")?;

                out.sha256
            }
            FetchUrl::TarballUrl(url) => {
                let out = Command::new("nix-prefetch-url")
                    .arg("--name")
                    .arg(&derivation_name)
                    .arg("--unpack")
                    .arg("--type")
                    .arg("sha256")
                    .arg(&url)
                    .output()
                    .await
                    .context("failed to run nix-prefetch-url process")?;
                if !out.status.success() {
                    return Err(anyhow!(
                        "process failed with stderr:\n{}",
                        String::from_utf8_lossy(&out.stderr[..])
                    ));
                }

                let stdout =
                    std::str::from_utf8(&out.stdout[..]).context("invalid utf8 in stdout")?;

                stdout.trim_end().to_string()
            }
        };

        NixHash::from_nix_nixbase32(&format!("sha256:{hash}"))
            .ok_or(anyhow!("failed to decode outputted nixbase32 hash"))
    }

    fn cache_key((_, commit_id): &Self::Args) -> Self::CacheKey {
        *commit_id
    }
}

impl FetchersHandle {
    pub async fn prefetch_by_ref_or_commit_id(&self, repo_url: &RepoUrl, git_ref_or_commit_id: &GitRefOrCommitId) -> Result<(git2::Oid, NixHash)> {
        let commit_id = self
            .resolve_ref_or_commit_id(repo_url, git_ref_or_commit_id)
            .await
            .context("failed to resolve git ref")?
            .ok_or(anyhow!("git ref not found in repository"))?;

        let nix_hash = self
            .nix_prefetch_git(&(repo_url.clone(), commit_id.clone()))
            .await
            .context("failed to prefetch repo by commit id")?;

        Ok((commit_id, nix_hash))
    }
}
