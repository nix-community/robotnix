use anyhow::{Error, Result};
use crate::execute::{ExecuteOnState, ManifestState};
use enum_dispatch::enum_dispatch;
use hard_xml::XmlRead;
use repo_types::{GitRef, GitRefSuffix, GitRefOrCommitId, Groups, RepoUrl};
use serde::{Deserialize, Serialize};
use std::str::FromStr;
use std::path::PathBuf;
use std::vec::Vec;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct RemoteName(pub String);
impl FromStr for RemoteName {
    type Err = Error;

    fn from_str(x: &str) -> Result<Self> {
        Ok(Self(x.to_string()))
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct RemoteBaseUrl(pub String);
impl FromStr for RemoteBaseUrl {
    type Err = Error;

    fn from_str(x: &str) -> Result<Self> {
        Ok(Self(x.to_string()))
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct RelativeUrl(pub String);
impl FromStr for RelativeUrl {
    type Err = Error;

    fn from_str(x: &str) -> Result<Self> {
        Ok(Self(x.to_string()))
    }
}

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
                    .rsplitn(3, '/')
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
pub struct GitRepoRevision(pub String);
impl FromStr for GitRepoRevision {
    type Err = Error;

    fn from_str(x: &str) -> Result<Self> {
        Ok(Self(x.to_string()))
    }
}

impl GitRepoRevision {
    pub fn to_git_ref(&self) -> GitRefOrCommitId {
        // NOTE(cyclic-pentane): this function is cringe jankmaxxing but unfortunately the crappy
        // git-repo manifest format forces us to do this
        if let Ok(commit_id) = git2::Oid::from_str(&self.0) {
            GitRefOrCommitId::CommitId(commit_id)
        } else if self.0.starts_with("refs/") {
            GitRefOrCommitId::GitRef(GitRef(self.0.clone()))
        } else {
            GitRefOrCommitId::GitRefSuffix(GitRefSuffix(self.0.clone()))
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(tag = "remote")]
pub struct Remote {
    #[xml(attr = "name")]
    pub name: RemoteName,

    #[xml(attr = "fetch")]
    pub repo_url_base: RemoteBaseUrl,

    #[xml(attr = "revision")]
    pub default_revision: Option<GitRepoRevision>,
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(tag = "default")]
pub struct DefaultRemote {
    #[xml(attr = "remote")]
    pub remote: RemoteName,

    #[xml(attr = "revision")]
    pub default_revision: Option<GitRepoRevision>,
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(strict(unknown_attribute, unknown_element))]
#[xml(tag = "linkfile")]
pub struct LinkFile {
    #[xml(attr = "src")]
    pub src: PathBuf,

    #[xml(attr = "dest")]
    pub dest: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(strict(unknown_attribute, unknown_element))]
#[xml(tag = "copyfile")]
pub struct CopyFile {
    #[xml(attr = "src")]
    pub src: PathBuf,

    #[xml(attr = "dest")]
    pub dest: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(tag = "project")]
pub struct Project {
    #[xml(attr = "name")]
    pub relative_url: RelativeUrl,

    #[xml(attr = "path")]
    pub source_tree_path: Option<PathBuf>,

    #[xml(attr = "remote")]
    pub remote: Option<RemoteName>,

    #[xml(attr = "revision")]
    pub revision: Option<GitRepoRevision>,

    #[xml(attr = "groups", default)]
    pub groups: Groups,

    #[xml(child = "linkfile")]
    pub linkfiles: Vec<LinkFile>,

    #[xml(child = "copyfile")]
    pub copyfiles: Vec<CopyFile>,
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(strict(unknown_attribute, unknown_element))]
#[xml(tag = "extend-project")]
pub struct ExtendProject {
    #[xml(attr = "name")]
    pub relative_url: RelativeUrl,

    #[xml(attr = "path")]
    pub match_old_source_tree_path: Option<PathBuf>,

    #[xml(attr = "dest-path")]
    pub source_tree_path: Option<PathBuf>,

    #[xml(attr = "remote")]
    pub remote: Option<RemoteName>,

    #[xml(attr = "revision")]
    pub revision: Option<GitRepoRevision>,

    #[xml(attr = "groups", default)]
    pub groups: Groups,

    #[xml(child = "linkfile")]
    pub linkfiles: Vec<LinkFile>,

    #[xml(child = "copyfile")]
    pub copyfiles: Vec<CopyFile>,
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(strict(unknown_attribute, unknown_element))]
#[xml(tag = "remove-project")]
pub struct RemoveProject {
    #[xml(attr = "name")]
    pub relative_url: Option<RelativeUrl>,

    #[xml(attr = "path")]
    pub source_tree_path: Option<PathBuf>,

    #[xml(attr = "optional")]
    pub optional: bool,
    // unsupported attr: base-rev
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(strict(unknown_attribute, unknown_element))]
#[xml(tag = "include")]
pub struct Include {
    #[xml(attr = "name")]
    pub path: PathBuf,
    // unsupported attr: groups, revision (because I haven't figured out the overriding behaviour yet)
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[enum_dispatch(ExecuteOnState)]
pub enum Instruction {
    #[xml(tag = "remote")]
    Remote(Remote),

    #[xml(tag = "default")]
    DefaultRemote(DefaultRemote),

    #[xml(tag = "project")]
    Project(Project),

    #[xml(tag = "extend-project")]
    ExtendProject(ExtendProject),

    #[xml(tag = "remove-project")]
    RemoveProject(RemoveProject),
    // unsupported children: notice, manifest-server, submanifest, repo-hooks, superproject, contactinfo
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
pub enum Item {
    #[xml(
        tag = "remote",
        tag = "default",
        tag = "project",
        tag = "extend-project",
        tag = "remove-project",
    )]
    Instruction(Instruction),

    #[xml(tag = "include")]
    Include(Include),
}

#[derive(Clone, Debug, PartialEq, Eq, XmlRead)]
#[xml(tag = "manifest")]
pub struct Manifest {
    #[xml(
        child = "remote",
        child = "default",
        child = "project",
        child = "extend-project",
        child = "remove-project",
        child = "include"
    )]
    pub items: Vec<Item>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newtype_fields() {
        let remote_str = "<remote name=\"github\" fetch=\"..\" revision=\"lineage-23.2\" />";
        let remote = Remote {
            name: RemoteName("github".to_string()),
            repo_url_base: RemoteBaseUrl("..".to_string()),
            default_revision: Some(GitRepoRevision("lineage-23.2".to_string())),
        };
        assert_eq!(
            Remote::from_str(remote_str).unwrap(),
            remote,
        );
    }

    #[test]
    fn vecs_in_struct() {
        let project_str = "
          <project path=\"build/bazel\" name=\"platform/build/bazel\" groups=\"pdk,made_up_group_for_testing\" remote=\"aosp\" >
            <linkfile src=\"bazel.WORKSPACE\" dest=\"WORKSPACE\" />
            <linkfile src=\"bazel.BUILD\" dest=\"BUILD\" />
          </project>
        ";

        let project = Project {
            relative_url: RelativeUrl("platform/build/bazel".to_string()),
            source_tree_path: Some(PathBuf::from("build/bazel".to_string())),
            remote: Some(RemoteName("aosp".to_string())),
            revision: None,
            groups: Groups(
                vec!["pdk".to_string(), "made_up_group_for_testing".to_string()]
            ),
            linkfiles: vec![
                LinkFile {
                    src: PathBuf::from("bazel.WORKSPACE"),
                    dest: PathBuf::from("WORKSPACE"),
                },
                LinkFile {
                    src: PathBuf::from("bazel.BUILD"),
                    dest: PathBuf::from("BUILD"),
                },
            ],
            copyfiles: vec![],
        };

        assert_eq!(
            Project::from_str(project_str).unwrap(),
            project,
        );
    }

    #[test]
    fn manifest_instruction_enum() {
        let manifest_str = "
            <manifest>
                <remote name=\"github\" fetch=\"https://github.com/GrapheneOS\" revision=\"main\"/>
                <project path=\"build/bazel\" name=\"platform/build/bazel\" groups=\"pdk,made_up_group_for_testing\" remote=\"aosp\" >
                  <linkfile src=\"bazel.WORKSPACE\" dest=\"WORKSPACE\" />
                  <linkfile src=\"bazel.BUILD\" dest=\"BUILD\" />
                </project>

                <notice>blahblah</notice>

                <include name=\"foo/bar.xml\" />
            </manifest>
        ";
        let manifest = Manifest {
            items: vec![
                Item::Instruction(Instruction::Remote(Remote {
                    name: RemoteName("github".to_string()),
                    repo_url_base: RemoteBaseUrl("https://github.com/GrapheneOS".to_string()),
                    default_revision: Some(GitRepoRevision("main".to_string())),
                })),
                Item::Instruction(Instruction::Project(Project {
                    relative_url: RelativeUrl("platform/build/bazel".to_string()),
                    source_tree_path: Some(PathBuf::from("build/bazel".to_string())),
                    remote: Some(RemoteName("aosp".to_string())),
                    revision: None,
                    groups: Groups(
                        vec!["pdk".to_string(), "made_up_group_for_testing".to_string()]
                    ),
                    linkfiles: vec![
                        LinkFile {
                            src: PathBuf::from("bazel.WORKSPACE"),
                            dest: PathBuf::from("WORKSPACE"),
                        },
                        LinkFile {
                            src: PathBuf::from("bazel.BUILD"),
                            dest: PathBuf::from("BUILD"),
                        },
                    ],
                    copyfiles: vec![],
                })),
                Item::Include(Include {
                    path: PathBuf::from("foo/bar.xml"),
                }),
            ],
        };

        assert_eq!(
            Manifest::from_str(manifest_str).unwrap(),
            manifest,
        );
    }
}
