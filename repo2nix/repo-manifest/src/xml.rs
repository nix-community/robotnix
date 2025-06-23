use serde::Deserialize;
use std::fs::File;
use std::io::{self, BufReader};
use std::path::{Path, PathBuf};
use std::vec::Vec;
use thiserror::Error;

#[derive(Debug, Deserialize, Clone)]
pub struct Remote {
    #[serde(rename = "@name")]
    pub name: String,

    #[serde(rename = "@fetch")]
    pub fetch: String,

    #[serde(rename = "@pushurl")]
    pub pushurl: Option<String>,

    #[serde(rename = "@review")]
    pub review: Option<String>,

    #[serde(rename = "@revision")]
    pub revision: Option<String>,
    // unsupported attrs: alias, annotation
}

#[derive(Debug, Deserialize, Clone)]
pub struct DefaultRemote {
    #[serde(rename = "@remote")]
    pub remote: String,

    #[serde(rename = "@revision")]
    pub revision: Option<String>,

    #[serde(rename = "@dest-branch")]
    pub dest_branch: Option<String>,

    #[serde(rename = "@sync-j")]
    pub sync_j: Option<u64>,

    #[serde(rename = "@sync-c")]
    pub sync_c: Option<bool>,
    // unsupported attrs: upstream, sync-s
}

#[derive(Debug, Deserialize, Clone)]
pub struct Project {
    #[serde(rename = "@name")]
    pub name: String,

    #[serde(rename = "@path")]
    pub path: PathBuf,

    #[serde(rename = "@remote")]
    pub remote: Option<String>,

    #[serde(rename = "@revision")]
    pub revision: Option<String>,

    #[serde(rename = "@dest-branch")]
    pub dest_branch: Option<String>,

    #[serde(rename = "@groups")]
    pub groups: Option<String>,

    #[serde(rename = "@sync-c")]
    pub sync_c: Option<bool>,

    #[serde(rename = "@clone-depth")]
    pub clone_depth: Option<String>,

    #[serde(rename = "@force-path")]
    pub force_path: Option<String>,

    #[serde(rename = "linkfile", default)]
    pub linkfiles: Vec<LinkCopyFile>,

    #[serde(rename = "copyfile", default)]
    pub copyfiles: Vec<LinkCopyFile>,
    // unsupported attrs: upstream, sync-c, annotation
}

#[derive(Debug, Deserialize, Clone)]
pub struct LinkCopyFile {
    #[serde(rename = "@src")]
    pub src: PathBuf,

    #[serde(rename = "@dest")]
    pub dest: PathBuf,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Include {
    #[serde(rename = "@name")]
    pub name: PathBuf,

    #[serde(rename = "@groups")]
    pub groups: Option<String>,
    // unsupported attrs: revision (because I haven't figured out the overriding behaviour yet)
}

#[derive(Debug, Deserialize, Clone)]
pub struct ContactInfo {
    #[serde(rename = "@bugurl")]
    pub bugurl: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Manifest {
    #[serde(rename = "remote", default)]
    pub remotes: Vec<Remote>,

    #[serde(rename = "default")]
    pub default: Option<DefaultRemote>,

    #[serde(rename = "project", default)]
    pub projects: Vec<Project>,

    #[serde(rename = "include", default)]
    pub includes: Vec<Include>,

    pub contactinfo: Option<ContactInfo>,
    // unsupported children: submanifest, extend-project, remove-project, repo-hooks, superproject
}

#[derive(Debug, Error)]
pub enum ManifestReadFileError {
    #[error("error reading file")]
    IOError(#[from] io::Error),

    #[error("malformed XML")]
    MalformedXMLError(#[from] quick_xml::errors::serialize::DeError),
}

pub fn read_manifest_file(path: &Path) -> Result<Manifest, ManifestReadFileError> {
    let f = File::open(path).map_err(ManifestReadFileError::IOError)?;
    let mut reader = BufReader::new(f);

    quick_xml::de::from_reader(&mut reader).map_err(ManifestReadFileError::MalformedXMLError)
}
