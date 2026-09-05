use clap::Parser;
use nix_compat::nixhash::NixHash;
use repo_manifest::xml::Groups;
use repo_types::FetchUrl;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct DeviceName(pub String);

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Source {
    derivation_name: String,
    fetch_url: FetchUrl,
    mirror_path: PathBuf,
    #[serde(with = "repo_types::custom_serde::nix_hash")]
    hash: NixHash,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Project {
    src: Source,
    groups: Groups,
    linkfiles: BTreeMap<PathBuf, PathBuf>,
    copyfiles: BTreeMap<PathBuf, PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManifestLockfile {
    common: BTreeMap<PathBuf, Project>,
    device_specific: BTreeMap<DeviceName, BTreeMap<PathBuf, Project>>,
}

#[derive(Parser)]
pub struct CommonCliArgs {
    #[arg(short = 'j', long, default_value_t = 4)]
    pub fetcher_tasks: u64,

    #[arg(long)]
    pub nixhash_lockfile: Option<PathBuf>,
}
