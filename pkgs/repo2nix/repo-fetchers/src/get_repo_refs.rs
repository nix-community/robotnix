use anyhow::{Context, Result, anyhow};
use crate::{Fetcher, FetchersHandle};
use log::info;
use repo_types::{ForgeSpecificRepoUrl, GitRef, GitRefSuffix, GitRefOrCommitId, GitRefType, RepoUrl};
use serde::Deserialize;
use std::collections::BTreeMap;
use tokio::process::Command;
use reqwest::header::HeaderMap;

#[derive(Default)]
pub(crate) struct GetRepoRefs;

impl Fetcher for GetRepoRefs {
    type Args = (RepoUrl, GitRefType);
    type CacheKey = (RepoUrl, GitRefType);
    type Output = BTreeMap<GitRef, git2::Oid>;

    async fn execute(
        &mut self,
        (repo_url, GitRefType(ref_type)): &Self::Args,
    ) -> Result<Self::Output> {
        info!("git ls-remote {}", repo_url.0);
        let out = Command::new("git")
            .arg("ls-remote")
            .arg(&repo_url.0)
            .arg(&format!("refs/{ref_type}/*"))
            .output()
            .await
            .context("failed to run git process")?;
        if !out.status.success() {
            return Err(anyhow!(
                "process failed with stderr:\n{}",
                String::from_utf8_lossy(&out.stderr[..])
            ));
        }

        let stdout = str::from_utf8(&out.stdout[..]).context("invalid utf8 in stdout")?;
        let mut refs = BTreeMap::new();
        for line in stdout.split('\n') {
            match &line.split('\t').collect::<Vec<_>>()[..] {
                [commit, git_ref_str] => {
                    let commit =
                        git2::Oid::from_str(commit).context("failed to parse commit id")?;
                    let git_ref = GitRef(git_ref_str.to_string());
                    refs.insert(git_ref, commit);
                }
                _ => return Err(anyhow!("invalid git ls-remote output line: {}", line)),
            }
        }
        Ok(refs)
    }

    fn cache_key(args: &Self::Args) -> Self::CacheKey {
        args.clone()
    }
}

impl FetchersHandle {
    // NOTE(cyclic-pentane): Gitiles has undocumented support for filtering the refs returned by the
    // `+refs` endpoint, e.g. calling GET https://android.googlesource.com/platform/build/+refs/heads?format=JSON returns all refs that have the type `heads`.
    // Sauce: https://gerrit.googlesource.com/gitiles/+/67c7844b7f7f228229c037cf297296874f50692c/java/com/google/gitiles/RefServlet.java#202
    async fn get_repo_refs_gitiles(
        &self,
        instance: &str,
        path: &str,
        GitRefType(ref_type): &GitRefType,
    ) -> Result<BTreeMap<GitRef, git2::Oid>> {
        let resp_json = self
            .http_get(
                &(
                    reqwest::Url::parse(&format!("https://{instance}/{path}/+refs/{ref_type}?format=JSON"))
                    .context("failed to parse Gitiles API URL")?,
                    HeaderMap::new(),
                )
            )
            .await
            .context("failed to wait for http_get fetcher")?;

        // https://gerrit.googlesource.com/gitiles/+/master/Documentation/api-reference.md#formatting
        // I have no clue why this is supposed to protect against XSS.
        let resp_json = resp_json
            .strip_prefix(")]}'\n")
            .with_context(|| format!("Gitiles API response missing XSS protection prefix: {resp_json}"))?;

        #[derive(Deserialize)]
        struct GitilesCommit<'a> {
            value: &'a str,
        }

        let refs: BTreeMap<&str, GitilesCommit> = serde_json::from_str(&resp_json)
            .context("failed to deserialize Gitiles API response")?;

        let refs = refs
            .into_iter()
            .map(|(x, y)| {
                Ok((
                    GitRef(format!("refs/{ref_type}/{x}")),
                    git2::Oid::from_str(y.value).context("failed to parse commit id")?,
                ))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        Ok(refs)
    }

    async fn get_repo_refs_github(
        &self,
        owner: &str,
        repo: &str,
        GitRefType(ref_type): &GitRefType,
    ) -> Result<BTreeMap<GitRef, git2::Oid>> {
        let resp_json = self
            .http_get(
                &(
                    reqwest::Url::parse(&format!(
                        "https://api.github.com/repos/{owner}/{repo}/git/matching-refs/{ref_type}"
                    ))
                    .context("failed to parse GitHub API URL")?,
                    {
                        let mut hm = HeaderMap::new();
                        if let Ok(token) = std::env::var("ROBOTNIX_GITHUB_TOKEN") {
                            hm.insert("Authorization", format!("Bearer {token}").parse().context("invalid GitHub API token value")?);
                        }
                        hm
                    },
                )
            )
            .await
            .context("failed to wait for http_get fetcher")?;

        #[derive(Deserialize)]
        struct GithubCommit<'a> {
            sha: &'a str,
        }

        #[derive(Deserialize)]
        struct GithubRef<'a> {
            r#ref: &'a str,
            object: GithubCommit<'a>,
        }

        let resp: Vec<GithubRef> = serde_json::from_str(&resp_json)
            .context("failed to deserialize GitHub API response")?;

        let refs = resp
            .into_iter()
            .map(|x| {
                Ok((
                    GitRef(x.r#ref.to_string()),
                    git2::Oid::from_str(x.object.sha).context("failed to parse commit id")?,
                ))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        Ok(refs)
    }

    async fn get_repo_refs_gitlab(
        &self,
        instance: &str,
        path: &str,
        GitRefType(ref_type): &GitRefType,
    ) -> Result<BTreeMap<GitRef, git2::Oid>> {
        #[derive(Deserialize)]
        struct GitlabCommit<'a> {
            id: &'a str,
        }

        #[derive(Deserialize)]
        struct GitlabBranchOrTag<'a> {
            name: &'a str,
            commit: GitlabCommit<'a>,
        }

        let path = urlencoding::encode(path);
        match &ref_type[..] {
            "heads" => {
                let resp_json = self
                    .http_get(
                        &(
                            reqwest::Url::parse(&format!(
                                "https://{instance}/api/v4/projects/{path}/repository/branches"
                            ))
                            .context("failed to parse GitLab API URL")?,
                            HeaderMap::new(),
                        )
                    )
                    .await
                    .context("failed to wait for http_get fetcher")?;

                let resp: Vec<GitlabBranchOrTag> = serde_json::from_str(&resp_json)
                    .context("failed to parse GitLab API response")?;

                let branches = resp
                    .into_iter()
                    .map(|x| {
                        Ok((
                            GitRef(format!("refs/heads/{}", x.name)),
                            git2::Oid::from_str(x.commit.id)
                                .context("failed to parse commit id")?,
                        ))
                    })
                    .collect::<Result<BTreeMap<_, _>>>()?;
                Ok(branches)
            }
            "tags" => {
                let resp_json = self
                    .http_get(
                        &(
                            reqwest::Url::parse(&format!(
                                "https://{instance}/api/v4/projects/{path}/repository/tags"
                            ))
                            .context("failed to parse GitLab API URL")?,
                            HeaderMap::new(),
                        )
                    )
                    .await
                    .context("failed to wait for http_get fetcher")?;

                let resp: Vec<GitlabBranchOrTag> = serde_json::from_str(&resp_json)
                    .context("failed to parse GitLab API response")?;

                let tags = resp
                    .into_iter()
                    .map(|x| {
                        Ok((
                            GitRef(format!("refs/tags/{}", x.name)),
                            git2::Oid::from_str(x.commit.id)
                                .context("failed to parse commit id")?,
                        ))
                    })
                    .collect::<Result<BTreeMap<_, _>>>()?;
                Ok(tags)
            }
            ref_type => Err(anyhow!("unsupported GitLab ref_type `{ref_type}`)")),
        }
    }

    pub async fn get_repo_refs_with_apis(
        &self,
        url: &RepoUrl,
        ref_type: &GitRefType,
    ) -> Result<BTreeMap<GitRef, git2::Oid>> {
        match ForgeSpecificRepoUrl::from_repo_url(url) {
            ForgeSpecificRepoUrl::Gitiles { instance, path } => {
                self.get_repo_refs_gitiles(&instance, &path, &ref_type).await
            }
            ForgeSpecificRepoUrl::Github { owner, repo } => {
                self.get_repo_refs_github(&owner, &repo, &ref_type).await
            }
            ForgeSpecificRepoUrl::Gitlab { instance, path } => {
                self.get_repo_refs_gitlab(&instance, &path, &ref_type).await
            }
            ForgeSpecificRepoUrl::Generic { repo_url } => {
                self.get_repo_refs(&(repo_url, ref_type.clone())).await
            }
        }
    }

    pub async fn get_branches_and_tags(&self, url: &RepoUrl) -> Result<BTreeMap<GitRef, git2::Oid>> {
        let mut refs = self
            .get_repo_refs_with_apis(url, &GitRefType("heads".to_string()))
            .await?;
        let mut tags = self
            .get_repo_refs_with_apis(url, &GitRefType("tags".to_string()))
            .await?;
        refs.append(&mut tags);
        Ok(refs)
    }

    pub async fn resolve_ref_or_commit_id(&self, url: &RepoUrl, ref_or_commit: &GitRefOrCommitId) -> Result<git2::Oid> {
        if let GitRefOrCommitId::CommitId(commit_id) = ref_or_commit {
            return Ok(commit_id.clone())
        }

        let refs = self
            .get_branches_and_tags(url)
            .await
            .context("failed to get all branches and tags of repo")?;
        let matching_refs = refs
            .into_iter()
            .filter(|(GitRef(name), _)| {
                match ref_or_commit {
                    GitRefOrCommitId::GitRef(GitRef(git_ref)) => name == git_ref,
                    GitRefOrCommitId::GitRefSuffix(GitRefSuffix(suffix)) => name.split('/').last().unwrap() == suffix,
                    _ => panic!(),
                }
            })
            .collect::<Vec<_>>();
        match &matching_refs[..] {
            [] => Err(anyhow!("ref {ref_or_commit:?} not found")),
            [(_, commit_id)] => Ok(*commit_id),
            _ => Err(anyhow!("multiple matching refs found: {matching_refs:?}")),
        }
    }
}
