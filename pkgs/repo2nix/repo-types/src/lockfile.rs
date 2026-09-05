use crate::{FetchUrl, Groups};
use nix_compat::nixhash::NixHash;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct DeviceName(pub String);

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Source {
    pub derivation_name: String,
    #[serde(with = "crate::custom_serde::oid")]
    pub commit_id: git2::Oid,
    pub fetch_url: FetchUrl,
    pub mirror_path: PathBuf,
    #[serde(with = "crate::custom_serde::nix_hash")]
    pub hash: NixHash,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Project {
    pub src: Source,
    pub groups: Groups,
    pub linkfiles: BTreeMap<PathBuf, PathBuf>,
    pub copyfiles: BTreeMap<PathBuf, PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManifestLockfile {
    pub common: BTreeMap<PathBuf, Project>,
    pub device_specific: BTreeMap<DeviceName, BTreeMap<PathBuf, Project>>,
}
