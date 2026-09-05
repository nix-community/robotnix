use anyhow::{Result, Error};
use serde::{Serialize, Deserialize};
use std::str::FromStr;
use std::collections::BTreeSet;
use std::path::PathBuf;

pub mod lockfile;
pub mod custom_serde;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct GitRef(pub String);

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct GitRefSuffix(pub String);

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum GitRefOrCommitId {
    GitRef(GitRef),
    GitRefSuffix(GitRefSuffix),
    CommitId(git2::Oid),
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct GitRefType(pub String);

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct RepoUrl(pub String);

// TODO(cyclic-pentane): make these configurable maybe?
const GITILES_INSTANCES: &[&str] = &["android.googlesource.com"];
const GITLAB_INSTANCES: &[&str] = &["gitlab.com"];

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum ForgeSpecificRepoUrl {
    Generic { repo_url: RepoUrl },
    Gitiles { instance: String, path: String },
    Github { owner: String, repo: String },
    Gitlab { instance: String, path: String },
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum FetchUrl {
    GitRemote {
        repo_url: RepoUrl,
        #[serde(with = "custom_serde::oid")]
        commit_id: git2::Oid,
    },
    TarballUrl(String),
}

impl ForgeSpecificRepoUrl {
    pub fn from_repo_url(repo_url: &RepoUrl) -> Self {
        if let Some((instance, path)) = GITILES_INSTANCES
            .into_iter()
            .filter_map(|instance| {
                repo_url
                    .0
                    .strip_prefix(&format!("https://{instance}/"))
                    .map(|path| (instance, path))
            })
            .next()
        {
            Self::Gitiles {
                instance: instance.to_string(),
                path: path.to_string(),
            }
        } else if let Some([owner, repo]) = repo_url
            .0
            .strip_prefix("https://github.com/")
            .map(|x: &str| x.split('/').collect::<Vec<_>>())
            .as_deref()
        {
            Self::Github {
                owner: owner.to_string(),
                repo: repo.to_string(),
            }
        } else if let Some((instance, path)) = GITLAB_INSTANCES
            .into_iter()
            .filter_map(|x| {
                repo_url
                    .0
                    .strip_prefix(&format!("https://{x}/"))
                    .map(|y| (x, y))
            })
            .next()
        {
            Self::Gitlab {
                instance: instance.to_string(),
                path: path.to_string(),
            }
        } else {
            Self::Generic {
                repo_url: repo_url.clone(),
            }
        }
    }

    pub fn derivation_pname(&self) -> String {
        // TODO(cyclic-pentane): we should also check for
        match self {
            Self::Generic { repo_url } => {
                let url_without_prefix = repo_url.0.splitn(2, "://").last().unwrap();
                let url_without_host = url_without_prefix.splitn(2, '/').last().unwrap();
                let url_without_suffix = url_without_host
                    .trim_end_matches('/')
                    .trim_end_matches(".git");
                url_without_suffix.replace('/', "-")
            }
            Self::Gitiles { path, .. } => path.trim_end_matches('/').replace('/', "-"),
            Self::Github { owner, repo } => format!("{owner}-{repo}"),
            Self::Gitlab { path, .. } => path.trim_end_matches('/').replace('/', "-"),
        }
    }

    pub fn derivation_name(&self, commit_id: &git2::Oid) -> String {
        format!(
            "{}-{}",
            &self.derivation_pname(),
            &commit_id.to_string()[..7],
        )
    }

    pub fn to_fetch_url(&self, commit_id: &git2::Oid) -> FetchUrl {
        match self {
            ForgeSpecificRepoUrl::Generic { repo_url } => FetchUrl::GitRemote {
                repo_url: repo_url.clone(),
                commit_id: *commit_id,
            },
            ForgeSpecificRepoUrl::Gitiles { instance, path } => FetchUrl::TarballUrl(
                format!("https://{instance}/{path}/+archive/{commit_id}.tar.gz"),
            ),
            ForgeSpecificRepoUrl::Github { owner, repo } => FetchUrl::TarballUrl(format!(
                    "https://github.com/{owner}/{repo}/archive/{commit_id}.tar.gz"
            )),
            ForgeSpecificRepoUrl::Gitlab { instance, path } => FetchUrl::TarballUrl(format!(
                    "https://{}/api/v4/projects/{}/repository/archive?sha={}",
                    instance,
                    urlencoding::encode(&path),
                    commit_id,
            )),
        }
    }

    pub fn mirror_path(&self) -> PathBuf {
        match self {
            ForgeSpecificRepoUrl::Generic { repo_url } => {
                todo!()
            },
            ForgeSpecificRepoUrl::Gitiles { instance, path } => PathBuf::from(instance).join(path),
            ForgeSpecificRepoUrl::Github { owner, repo } => PathBuf::from("github.com").join(owner).join(repo),
            ForgeSpecificRepoUrl::Gitlab { instance, path } => PathBuf::from(instance).join(path),
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct Groups(pub BTreeSet<String>);
impl FromStr for Groups {
    type Err = anyhow::Error;

    fn from_str(x: &str) -> Result<Self> {
        Ok(Self(x.split(",").map(|x| x.to_string()).collect()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derivation_pname() {
        assert_eq!(
            ForgeSpecificRepoUrl::from_repo_url(&RepoUrl(
                "https://android.googlesource.com/platform/manifest/".to_string()
            ))
            .derivation_pname(),
            "platform-manifest",
        );
        assert_eq!(
            ForgeSpecificRepoUrl::from_repo_url(&RepoUrl(
                "https://github.com/LineageOS/android_device_nvidia_foster/".to_string()
            ))
            .derivation_pname(),
            "LineageOS-android_device_nvidia_foster",
        );
        assert_eq!(
            ForgeSpecificRepoUrl::from_repo_url(&RepoUrl(
                "https://gitlab.com/CalyxOS/platform_manifest/".to_string()
            ))
            .derivation_pname(),
            "CalyxOS-platform_manifest",
        );
        assert_eq!(
            ForgeSpecificRepoUrl::from_repo_url(&RepoUrl("https://some-random-shithole-forge.tk/totally_legit_rom/proprietary_firmware_cao_ni_ma.git".to_string())).derivation_pname(),
            "totally_legit_rom-proprietary_firmware_cao_ni_ma",
        );
    }
}
