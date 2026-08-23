use repo_types::{GitRef, GitRefOrCommitId, RepoUrl};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::vec::Vec;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct RemoteName(String);

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct RemoteBaseUrl(String);

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct RelativeUrl(String);

impl RemoteBaseUrl {
    pub fn join_parts(
        &self,
        manifest_url: &RepoUrl,
        project_relative_url: &RelativeUrl,
    ) -> RepoUrl {
        if self.0 == ".." {
            RepoUrl(format!(
                "{}/{}",
                manifest_url
                    .0
                    .trim_end_matches('/')
                    .rsplitn(2, '/')
                    .last()
                    .unwrap(),
                project_relative_url.0,
            ))
        } else {
            RepoUrl(format!(
                "{}/{}",
                self.0.trim_end_matches('/'),
                project_relative_url.0,
            ))
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct GitRepoRevision(String);

impl GitRepoRevision {
    pub fn to_git_ref(&self) -> GitRefOrCommitId {
        // NOTE(cyclic-pentane): this function is cringe jankmaxxing but unfortunately the crappy
        // git-repo manifest format forces us to do this
        if let Ok(commit_id) = git2::Oid::from_str(&self.0) {
            GitRefOrCommitId::CommitId(commit_id)
        } else if self.0.starts_with("refs/") {
            GitRefOrCommitId::GitRef(GitRef(self.0.clone()))
        } else {
            GitRefOrCommitId::GitRef(GitRef(format!("refs/heads/{}", self.0)))
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Remote {
    #[serde(rename = "@name")]
    pub name: RemoteName,

    #[serde(rename = "@fetch")]
    pub repo_url_base: RemoteBaseUrl,

    #[serde(rename = "@revision")]
    pub default_revision: Option<GitRepoRevision>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct DefaultRemote {
    #[serde(rename = "@remote")]
    pub remote: RemoteName,

    #[serde(rename = "@revision")]
    pub default_revision: Option<GitRepoRevision>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct LinkCopyFile {
    #[serde(rename = "@src")]
    pub src: PathBuf,

    #[serde(rename = "@dest")]
    pub dest: PathBuf,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Project {
    #[serde(rename = "@name")]
    pub relative_url: RelativeUrl,

    #[serde(rename = "@path")]
    pub source_tree_path: Option<PathBuf>,

    #[serde(rename = "@remote")]
    pub remote: Option<RemoteName>,

    #[serde(rename = "@revision")]
    pub revision: Option<GitRepoRevision>,

    #[serde(rename = "@groups")]
    pub groups: Option<String>,

    #[serde(rename = "linkfile", default)]
    pub linkfiles: Vec<LinkCopyFile>,

    #[serde(rename = "copyfile", default)]
    pub copyfiles: Vec<LinkCopyFile>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExtendProject {
    #[serde(flatten)]
    pub project: Project,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct RemoveProject {
    #[serde(rename = "@name")]
    pub relative_url: RelativeUrl,

    #[serde(rename = "@path")]
    pub source_tree_path: Option<PathBuf>,

    #[serde(rename = "@optional")]
    pub optional: bool,
    // unsupported attr: base-rev
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Include {
    #[serde(rename = "@name")]
    pub name: PathBuf,

    #[serde(rename = "@groups")]
    pub groups: Option<String>,
    // unsupported attr: revision (because I haven't figured out the overriding behaviour yet)
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub enum ManifestInstruction {
    #[serde(rename = "remote")]
    Remote(Remote),

    #[serde(rename = "default")]
    DefaultRemote(DefaultRemote),

    #[serde(rename = "project")]
    Project(Project),

    #[serde(rename = "extend-project")]
    ExtendProject(ExtendProject),

    #[serde(rename = "remove-project")]
    RemoveProject(RemoveProject),

    #[serde(rename = "include")]
    Include(Include),
    // unsupported children: notice, manifest-server, submanifest, repo-hooks, superproject, contactinfo
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_instruction_enum_roundtrip() {
        let xml_str =
            "<remote name=\"github\" fetch=\"https://github.com/GrapheneOS\" revision=\"main\"/>";
        let mi = ManifestInstruction::Remote(Remote {
            name: RemoteName("github".to_string()),
            repo_url_base: RemoteBaseUrl("https://github.com/GrapheneOS".to_string()),
            default_revision: Some(GitRepoRevision("main".to_string())),
        });

        assert_eq!(xml_str, quick_xml::se::to_string(&mi).unwrap(),);

        assert_eq!(mi, quick_xml::de::from_str(xml_str).unwrap(),);
    }
}
