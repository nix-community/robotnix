use std::path::{Path, PathBuf};
use std::collections::HashMap;
use serde::{Serialize, Deserialize};
use url::{Url, ParseError};
use thiserror::Error;
use crate::xml::{self, read_manifest_file};

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
pub struct GitRepoRef {
    pub repo_url: Url,
    pub revision: String,
    pub fetch_lfs: bool,
    pub fetch_submodules: bool,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
pub enum Category {
    Default,
    DeviceSpecific(String),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
pub enum LineageDeps {
    MissingBranch,
    NoLineageDependenciesFile,
    Some(Vec<PathBuf>),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
pub struct Project {
    pub path: PathBuf,
    pub groups: Vec<String>,
    pub linkfiles: Vec<xml::LinkCopyFile>,
    pub copyfiles: Vec<xml::LinkCopyFile>,
    pub repo_ref: GitRepoRef,
    pub categories: Vec<Category>,
    pub lineage_deps: Option<LineageDeps>,
    pub active: bool,
}

#[derive(Debug)]
pub struct Remote {
    pub name: String,
    pub url: Url,
    pub revision: Option<String>,
}

#[derive(Debug)]
pub struct Manifest {
    pub base_url: String,
    pub remotes: HashMap<String, Remote>,
    pub default_remote: Option<Remote>,
    pub projects: HashMap<PathBuf, Project>,
}

#[derive(Debug, Error)]
pub enum RecursivelyReadManifestFilesError {
    #[error("error reading manifest file")]
    ManifestReadFileError {
        path: PathBuf,
        #[source]
        inner_error: xml::ManifestReadFileError
    },
    #[error("missing `path` attribute for `{0}`")]
    MissingPath(String),
    #[error("duplicate default remote tag")]
    DuplicateDefaultRemote, 
    #[error("duplicate remote `{0}`")]
    DuplicateRemote(String),
    #[error("duplicate project path `{0}`")]
    DuplicatePath(PathBuf),
    #[error("duplicate contactinfo")]
    DuplicateContactinfo,
}

pub fn merge_manifests(manifest: &mut xml::Manifest, submanifest: &xml::Manifest) -> Result<(), RecursivelyReadManifestFilesError> {
    if let Some(default_remote) = &submanifest.default {
        match manifest.default {
            None => manifest.default = Some(default_remote.clone()),
            Some(_) => return Err(RecursivelyReadManifestFilesError::DuplicateDefaultRemote),
        }
    }

    for remote in submanifest.remotes.iter() {
        if manifest.remotes.iter().any(|r| r.name == remote.name) {
            return Err(RecursivelyReadManifestFilesError::DuplicateRemote(remote.name.to_string()));
        }
        manifest.remotes.push(remote.clone());
    }

    for project in submanifest.projects.iter() {
        if manifest.projects.iter().any(|p| p.path.as_ref().unwrap() == project.path.as_ref().unwrap()) {
            return Err(RecursivelyReadManifestFilesError::DuplicatePath(project.path.as_ref().unwrap().to_path_buf()));
        }
        manifest.projects.push(project.clone());
    }

    if let Some(contactinfo) = &submanifest.contactinfo {
        match manifest.contactinfo {
            None => manifest.contactinfo = Some(contactinfo.clone()),
            Some(_) => return Err(RecursivelyReadManifestFilesError::DuplicateContactinfo),
        }
    }

    Ok(())
}

pub async fn recursively_read_manifest_files(root_path: &Path, manifest_file: &Path) -> Result<xml::Manifest, RecursivelyReadManifestFilesError> {
    let mut manifest = read_manifest_file(&root_path.join(manifest_file))
        .await
        .map_err(|e| RecursivelyReadManifestFilesError::ManifestReadFileError {
            path: root_path.to_path_buf(),
            inner_error: e,
        })?;

    for project in manifest.projects.iter() {
        if project.path.is_none() {
            return Err(RecursivelyReadManifestFilesError::MissingPath(project.name.clone()));
        }
    }

    let include_files: Vec<_> = manifest.includes.iter().map(|x| x.name.clone()).collect();
    for include in include_files.iter() {
        let submanifest = Box::pin(recursively_read_manifest_files(root_path, &include)).await?;
        merge_manifests(&mut manifest, &submanifest)?;
    }

    manifest.includes.clear();

    Ok(manifest)
}

pub fn join_repo_url(base_url: &Url, repo_name: &str) -> Url {
    let base_path = &Path::new(base_url.path());
    let path = base_path.join(&repo_name);
    let mut url = base_url.clone();
    // This unwrap should be safe, as repo_name is guaranteed to be valid UTF-8.
    url.set_path(path.to_str().unwrap());

    url
}

#[derive(Debug, Error)]
pub enum ResolveManifestError {
    #[error("couldn't parse URL")]
    ParseURL(#[from] url::ParseError),
    #[error("invalid relative remote url")]
    InvalidRelativeRemoteURL(String),
    #[error("invalid UTF-8 in path")]
    InvalidUTF8(PathBuf),
    #[error("unknown remote `{0}` in <default> tag")]
    DefaultRemoteNotFound(String),
    #[error("unknown remote `{1}` for project `{0}`")]
    RemoteNotFound(String, String),
    #[error("no remote defined for project `{0}`")]
    MissingRemote(String),
    #[error("no revision set for project `{0}`")]
    MissingRevision(String),
    #[error("no path set for project `{0}`")]
    MissingPath(String),
}

pub fn resolve_manifest(manifest_xml: &xml::Manifest, base_url: &Url) -> Result<Manifest, ResolveManifestError> {
    let mut manifest = Manifest {
        base_url: base_url.to_string(),
        remotes: HashMap::new(),
        default_remote: None,
        projects: HashMap::new(),
    };

    for remote_xml in manifest_xml.remotes.iter() {
        let url = match Url::parse(&remote_xml.fetch) {
            Ok(u) => Ok(u),
            Err(ParseError::RelativeUrlWithoutBase) => {
                let base_path = &Path::new(base_url.path());
                let path = base_path.parent().ok_or(ResolveManifestError::InvalidRelativeRemoteURL(remote_xml.fetch.clone()))?.join(&remote_xml.fetch);
                let mut url = base_url.clone();
                url.set_path(path.to_str().ok_or(ResolveManifestError::InvalidUTF8(path.clone()))?);

                Ok(url)
            },
            Err(e) => Err(ResolveManifestError::ParseURL(e)),
        }?;

        let remote = Remote {
            name: remote_xml.name.clone(),
            url: url,
            revision: remote_xml.revision.clone(),
        };
        manifest.remotes.insert(remote.name.clone(), remote);
    }

    if let Some(default_remote_xml) = &manifest_xml.default {
        let remote = manifest.remotes.get(&default_remote_xml.remote).ok_or(ResolveManifestError::DefaultRemoteNotFound(default_remote_xml.remote.clone()))?;
        manifest.default_remote = Some(Remote {
            name: remote.name.clone(),
            url: remote.url.clone(),
            revision: remote.revision.clone().or(default_remote_xml.revision.clone()),
        });
    }

    for project_xml in manifest_xml.projects.iter() {
        let name = &project_xml.name;
        let remote = match &project_xml.remote {
            Some(remote_name) => manifest
                .remotes
                .get(remote_name)
                .ok_or(ResolveManifestError::RemoteNotFound(name.clone(), remote_name.clone()))?,
            None => manifest.default_remote.as_ref().ok_or(ResolveManifestError::MissingRemote(name.clone()))?,
        };
        let project = Project {
            path: project_xml.path.clone().ok_or(ResolveManifestError::MissingPath(project_xml.name.clone()))?,
            groups: project_xml
                .groups
                .as_ref()
                .map(|x| x
                    .split(",")
                    .map(|y| y.to_string())
                    .collect()
                )
                .unwrap_or(vec![]),
            linkfiles: project_xml.linkfiles.clone(),
            copyfiles: project_xml.copyfiles.clone(),
            repo_ref: GitRepoRef {
                repo_url: join_repo_url(&remote.url, &project_xml.name),
                revision: project_xml
                    .revision
                    .as_ref()
                    .or(remote.revision.as_ref())
                    .ok_or(ResolveManifestError::MissingRevision(name.clone()))
                    .cloned()?,
                fetch_lfs: true,
                fetch_submodules: false,
            },
            categories: vec![Category::Default],
            lineage_deps: Some(LineageDeps::NoLineageDependenciesFile),
            active: true,
        };
        manifest.projects.insert(project.path.clone(), project);
    }

    Ok(manifest)
}
