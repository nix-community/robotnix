#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct GitRef(pub String);

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum GitRefOrCommitId {
    GitRef(GitRef),
    CommitId(git2::Oid),
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct GitRefPrefix(pub String);

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
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
