use crate::Fetcher;
use anyhow::{Context, Result, anyhow};
use nix_compat::nixhash::NixHash;
use repo_types::{ForgeSpecificRepoUrl, RepoUrl};
use serde::Deserialize;
use tokio::process::Command;

#[derive(Default)]
pub(crate) struct NixPrefetchGit;

// TODO(cyclic-pentane): implement ROBOTNIX_GIT_MIRRORS in a sensible way
// should especially minimise code duplication between this module, get_repo_refs.rs, and the
// robotnix NixOS module system FOD invocations

enum PrefetcherCommand {
    GitRemote {
        repo_url: RepoUrl,
        commit_id: git2::Oid,
    },
    TarballUrl(String),
}

fn convert_url(repo_url: &RepoUrl, commit_id: &git2::Oid) -> (PrefetcherCommand, String) {
    let repo_url = ForgeSpecificRepoUrl::from_repo_url(repo_url);
    (
        match &repo_url {
            ForgeSpecificRepoUrl::Generic { repo_url } => PrefetcherCommand::GitRemote {
                repo_url: repo_url.clone(),
                commit_id: *commit_id,
            },
            ForgeSpecificRepoUrl::Gitiles { instance, path } => PrefetcherCommand::TarballUrl(
                format!("https://{instance}/{path}/+archive/{commit_id}.tar.gz"),
            ),
            ForgeSpecificRepoUrl::Github { owner, repo } => PrefetcherCommand::TarballUrl(format!(
                "https://github.com/{owner}/{repo}/archive/{commit_id}.tar.gz"
            )),
            ForgeSpecificRepoUrl::Gitlab { instance, path } => {
                PrefetcherCommand::TarballUrl(format!("https://{instance}/{path}/"))
            }
        },
        repo_url.derivation_name(commit_id),
    )
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
        let (repo_url, derivation_name) = convert_url(repo_url, commit_id);
        let hash = match repo_url {
            PrefetcherCommand::GitRemote {
                repo_url,
                commit_id,
            } => {
                let out = Command::new("nix-prefetch-git")
                    .arg("--name")
                    .arg(&derivation_name)
                    .arg("--rev")
                    .arg(&commit_id.to_string())
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

                #[derive(serde::Deserialize)]
                struct NixPrefetchGitOutput {
                    sha256: String,
                }

                let out: NixPrefetchGitOutput = serde_json::from_slice(&out.stdout[..])
                    .context("failed to deserialize nix-prefetch-git output")?;

                out.sha256
            }
            PrefetcherCommand::TarballUrl(url) => {
                let out = Command::new("nix-prefetch-url")
                    .arg("--name")
                    .arg(&derivation_name)
                    .arg("--unpack")
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

        NixHash::from_nix_nixbase32(&hash)
            .ok_or(anyhow!("failed to decode outputted nixbase32 hash"))
    }

    fn cache_key((_, commit_id): &Self::Args) -> Self::CacheKey {
        *commit_id
    }
}
