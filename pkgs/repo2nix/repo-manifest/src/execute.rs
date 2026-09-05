use anyhow::{anyhow, Error, Result};
use crate::xml::{
    DefaultRemote,
    GitRepoRevision,
    Groups,
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
use repo_types::{GitRefOrCommitId, RepoUrl};

#[derive(Debug, Clone)]
pub struct ResolvedRemote {
    base_url: RemoteBaseUrl,
    default_revision: Option<GitRefOrCommitId>,
}

#[derive(Debug, Clone)]
pub struct ResolvedProject {
    base_url: RemoteBaseUrl,
    revision: GitRefOrCommitId,
    source_tree_path: PathBuf,
    groups: Groups,
    linkfiles: BTreeMap<PathBuf, PathBuf>, // dest -> source
    copyfiles: BTreeMap<PathBuf, PathBuf>, // dest -> source
}

#[derive(Debug, Clone)]
pub struct ManifestState {
    manifest_url: RepoUrl,
    remotes: BTreeMap<RemoteName, ResolvedRemote>,
    default_remote: Option<(RemoteName, Option<GitRefOrCommitId>)>,
    projects: BTreeMap<RelativeUrl, ResolvedProject>,
}

impl ManifestState {
    pub fn new(manifest_url: RepoUrl) -> Self {
        ManifestState {
            manifest_url,
            remotes: BTreeMap::new(),
            default_remote: None,
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
        if let Some(_) = state.remotes.get(&self.name) {
            return Err(anyhow!("duplicate remote `{}`", self.name.0));
        }
        state.remotes.insert(
            self.name.clone(),
            ResolvedRemote {
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
        if let Some(_) = state.default_remote {
            return Err(anyhow!("duplicate <default /> statement"));
        }

        state.default_remote = Some(
            (
                self.remote.clone(),
                self.default_revision.as_ref().map(GitRepoRevision::to_git_ref),
            )
        );

        Ok(())
    }
}

impl ExecuteOnState for Project {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        if let Some(_) = state.projects.get(&self.relative_url) {
            return Err(anyhow!("duplicate project `{}`", self.relative_url.0));
        }

        let source_tree_path = self
            .source_tree_path
            .clone()
            .unwrap_or(PathBuf::from(&self.relative_url.0));

        let remote = self
            .remote
            .as_ref()
            .or(state.default_remote.as_ref().map(|x| &x.0))
            .ok_or(anyhow!("project `{}` is missing a remote", self.relative_url.0))?;

        let resolved_remote = state
            .remotes
            .get(&remote)
            .ok_or(anyhow!("unknown remote `{}`", &remote.0))?;

        let revision = self
            .revision
            .as_ref()
            .map(GitRepoRevision::to_git_ref)
            .or(resolved_remote.default_revision.clone())
            .or(state.default_remote.as_ref().and_then(|x| x.1.clone()))
            .ok_or(anyhow!("project `{}` is missing a revision", self.relative_url.0))?;

        state.projects.insert(
            self.relative_url.clone(),
            ResolvedProject {
                base_url: resolved_remote.base_url.clone(),
                revision,
                source_tree_path,
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
            },
        );

        Ok(())
    }
}

impl ExecuteOnState for ExtendProject {
    fn execute_on(&self, state: &mut ManifestState) -> Result<()> {
        let Some(project) = state
            .projects
            .get_mut(&self.relative_url)
        else {
            return Err(anyhow!("unknown project `{}`", self.relative_url.0));
        };

        if let Some(ref match_old_source_tree_path) = self.match_old_source_tree_path && *match_old_source_tree_path != project.source_tree_path {
            return Err(anyhow!(
                    "`path` attribute `{}` in <extend-project /> doesn't match old source tree path `{}` of project `{}`",
                    match_old_source_tree_path.display(),
                    project.source_tree_path.display(),
                    &self.relative_url.0,
            ));
        }

        if let Some(new_path) = &self.source_tree_path {
            project.source_tree_path = new_path.clone();
        }

        if let Some(remote) = &self.remote {
            project.base_url = state
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
            if !project.groups.0.contains(group) {
                project.groups.0.push(group.clone());
            }
        }

        for LinkFile { src, dest } in &self.linkfiles {
            project.linkfiles.insert(dest.clone(), src.clone());
        }

        for CopyFile { src, dest } in &self.copyfiles {
            project.copyfiles.insert(dest.clone(), src.clone());
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
                |(rel_url, project)|
                self.relative_url.as_ref().map(|x| x == *rel_url).unwrap_or(true) &&
                self.source_tree_path.as_ref().map(|x| *x == project.source_tree_path).unwrap_or(true)
            )
            .map(|(rel_url, _)| rel_url.clone())
            .collect();

        match &rel_urls_to_remove[..] {
            [] => if !self.optional { return Err(anyhow!("project to remove not found")); },
            [rel_url] => {
                state.projects.remove(&rel_url);
            },
            _ => return Err(anyhow!("<remove-project /> statement matched several projects")),
        }

        Ok(())
    }
}
