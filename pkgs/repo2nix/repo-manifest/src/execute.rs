use anyhow::{anyhow, Error, Result};
use crate::xml::{
    DefaultRemote,
    GitRepoRevision,
    Remote,
    RemoteName,
    RemoteBaseUrl,
    RelativeUrl,
    LinkFile,
    CopyFile,
    Project,
    ExtendProject,
    RemoveProject,
    Instruction,
};
use enum_dispatch::enum_dispatch;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use repo_types::{GitRefOrCommitId, Groups, RepoUrl};

#[derive(Debug, Clone)]
pub struct RemoteState {
    pub base_url: RemoteBaseUrl,
    pub default_revision: Option<GitRefOrCommitId>,
}

#[derive(Debug, Clone)]
pub struct ProjectState {
    pub base_url: RemoteBaseUrl,
    pub relative_url: RelativeUrl,
    pub revision: GitRefOrCommitId,
    pub groups: Groups,
    pub linkfiles: BTreeMap<PathBuf, PathBuf>, // dest -> source
    pub copyfiles: BTreeMap<PathBuf, PathBuf>, // dest -> source
}

#[derive(Debug, Clone)]
pub struct ManifestConfigState {
    pub manifest_url: RepoUrl,
    pub remotes: BTreeMap<RemoteName, RemoteState>,
    pub default_remote: Option<(RemoteName, Option<GitRefOrCommitId>)>,
}

#[derive(Debug, Clone)]
pub struct ManifestState {
    pub config: ManifestConfigState,
    pub projects: BTreeMap<PathBuf, ProjectState>,
}

impl ManifestState {
    pub fn new(manifest_url: RepoUrl) -> Self {
        ManifestState {
            config: ManifestConfigState {
                manifest_url,
                remotes: BTreeMap::new(),
                default_remote: None,
            },
            projects: BTreeMap::new(),
        }
    }
}

#[enum_dispatch]
pub trait ExecuteOnState {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()>;
}

impl ExecuteOnState for Remote {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        if let Some(_) = state.config.remotes.get(&self.name) {
            return Err(anyhow!("duplicate remote `{}`", self.name.0));
        }
        state.config.remotes.insert(
            self.name.clone(),
            RemoteState {
                base_url: self.repo_url_base.clone(),
                default_revision: self
                    .default_revision
                    .as_ref()
                    .map(GitRepoRevision::to_git_ref),
            },
        );

        Ok(())
    }
}

impl ExecuteOnState for DefaultRemote {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        if let Some(_) = state.config.default_remote {
            return Err(anyhow!("duplicate <default /> statement"));
        }

        state.config.default_remote = Some(
            (
                self.remote.clone(),
                self.default_revision.as_ref().map(GitRepoRevision::to_git_ref),
            )
        );

        Ok(())
    }
}

impl Project {
    pub fn add_to(&self, state: &mut ManifestState) -> Result<ProjectState> {
        let relpath = self
            .source_tree_path
            .as_ref()
            .map(PathBuf::to_owned)
            .unwrap_or(PathBuf::from(self.relative_url.0.clone()));

        if let Some(_) = state.projects.get(&relpath) {
            return Err(anyhow!("duplicate project `{}`", relpath.display()));
        }

        let source_tree_path = self
            .source_tree_path
            .clone()
            .unwrap_or(PathBuf::from(&self.relative_url.0));

        let remote = self
            .remote
            .as_ref()
            .or(state.config.default_remote.as_ref().map(|x| &x.0))
            .ok_or(anyhow!("project `{}` is missing a remote", self.relative_url.0))?;

        let resolved_remote = state
            .config
            .remotes
            .get(&remote)
            .ok_or(anyhow!("unknown remote `{}`", &remote.0))?;

        let revision = self
            .revision
            .as_ref()
            .map(GitRepoRevision::to_git_ref)
            .or(resolved_remote.default_revision.clone())
            .or(state.config.default_remote.as_ref().and_then(|x| x.1.clone()))
            .ok_or(anyhow!("project `{}` is missing a revision", self.relative_url.0))?;

        let project_state = ProjectState {
            base_url: resolved_remote.base_url.clone(),
            relative_url: self.relative_url.clone(),
            revision,
            groups: self.groups.clone(),
            linkfiles: self
                .linkfiles
                .iter()
                .map(|LinkFile { src, dest }| (dest.clone(), src.clone()))
                .collect(),
                copyfiles: self
                    .copyfiles
                    .iter()
                    .map(|CopyFile { src, dest }| (dest.clone(), src.clone()))
                    .collect(),
        };

        state.projects.insert(
            relpath,
            project_state.clone(),
        );

        Ok(project_state)
    }
}

impl ExecuteOnState for Project {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        self.add_to(state)?;
        Ok(())
    }
}

impl ExecuteOnState for ExtendProject {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        let matching_relpaths = state
            .projects
            .iter_mut()
            .filter(|(relpath, project)| self.relative_url == project.relative_url && self.match_old_source_tree_path.as_ref().map(|x| x == *relpath).unwrap_or(true))
            .map(|(relpath, _)| relpath.clone())
            .collect::<Vec<_>>();

        let old_relpath = match &matching_relpaths[..] {
            [] => return Err(anyhow!("no project in manifest matches <remove-project /> statement")),
            [relpath] => relpath,
            _ => return Err(anyhow!("<remove-project /> statement matches more than one project")),
        };

        {
            let project = state.projects.get_mut(old_relpath).unwrap();
            if let Some(remote) = &self.remote {
                project.base_url = state
                    .config
                    .remotes
                    .get(&remote)
                    .ok_or(anyhow!("remote `{}` not found", &remote.0))?
                    .base_url
                    .clone();
            }

            if let Some(revision) = &self.revision {
                project.revision = revision.to_git_ref();
            }

            for group in &self.groups.0 {
                project.groups.0.insert(group.clone());
            }

            for LinkFile { src, dest } in &self.linkfiles {
                project.linkfiles.insert(dest.clone(), src.clone());
            }

            for CopyFile { src, dest } in &self.copyfiles {
                project.copyfiles.insert(dest.clone(), src.clone());
            }
        }

        if let Some(new_relpath) = &self.source_tree_path {
            let project = state.projects.remove(old_relpath).unwrap();
            state.projects.insert(
                new_relpath.clone(),
                project,
            );
        }

        Ok(())
    }
}

impl ExecuteOnState for RemoveProject {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        let rel_urls_to_remove: Vec<_> = state
            .projects
            .iter()
            .filter(
                |(relpath, project)|
                self.relative_url.as_ref().map(|x| *x == project.relative_url).unwrap_or(true) &&
                self.source_tree_path.as_ref().map(|x| x == *relpath).unwrap_or(true)
            )
            .map(|(rel_url, _)| rel_url.clone())
            .collect();

        match &rel_urls_to_remove[..] {
            [] => if !self.optional { return Err(anyhow!("project to remove not found")); },
            [rel_url] => {
                state.projects.remove(rel_url);
            },
            _ => return Err(anyhow!("<remove-project /> statement matched several projects")),
        }

        Ok(())
    }
}
