use std::collections::{BTreeMap, HashMap};
use std::io;
use std::str;
use serde::{Serialize, Deserialize};
use url::Url;
use tokio::fs;
use tokio::process::Command;
use thiserror::Error;
use repo_manifest::xml::{
    read_manifest_file,
    ManifestReadFileError,
};
use repo_manifest::resolver::{
    GitRepoRef,
};
use crate::fetch::{
    nix_prefetch_git,
    NixPrefetchGitError,
    GitLsRemoteError,
};

#[derive(Debug)]
pub struct HudsonDeviceInfo {
    pub build_type: String,
    pub branch: String,
    pub period: String,
}

#[derive(Debug, Error)]
pub enum FetchHudsonDevicesError {
    #[error("couldn't fetch github:LineageOS/hudson")]
    Fetch(#[from] NixPrefetchGitError),
    #[error("couldn't read `lineage-build-targets` from Nix store")]
    IO(io::Error),
    #[error("couldn't parse `lineage-build-targets`: invalid line `{0}`")]
    ParseLine(String),
    #[error("invalid UTF8 in `lineage-build-targets`")]
    Utf8(str::Utf8Error),
}

pub async fn fetch_hudson_devices() -> Result<HashMap<String, HudsonDeviceInfo>, FetchHudsonDevicesError>  {
    let hudson_fetch = nix_prefetch_git(
        &Url::parse("https://github.com/LineageOS/hudson").unwrap(),
        "refs/heads/main",
        false,
        false,
    ).await?;

    let bytes = fs::read(&hudson_fetch.path.join("lineage-build-targets"))
        .await
        .map_err(FetchHudsonDevicesError::IO)?;

    let text = str::from_utf8(&bytes)
        .map_err(FetchHudsonDevicesError::Utf8)?;

    let mut devices = HashMap::new();
    for line in text.split("\n") {
        let line = line.trim();
        if line == "" || line.starts_with("#") {
            continue;
        }
        let fields: Vec<_> = line.split(" ").collect();
        match fields.as_slice() {
            [name, build_type, branch, period] => {
                devices.insert(name.to_string(), HudsonDeviceInfo {
                    build_type: build_type.to_string(),
                    branch: branch.to_string(),
                    period: period.to_string(),
                });

            },
            _ => return Err(FetchHudsonDevicesError::ParseLine(line.to_owned())),
        };
    }

    Ok(devices)
}

#[derive(Debug, Error)]
pub enum GetDeviceReposError {
    #[error("fetching github:LineageOS/mirror failed")]
    Fetch(#[from] NixPrefetchGitError),
    #[error("reading mirror manifest failed")]
    ReadMirrorManifest(#[from] ManifestReadFileError),
}

pub async fn get_device_repos() -> Result<Vec<(String, String)>, GetDeviceReposError> {
    let mirror_fetch = nix_prefetch_git(
        &Url::parse("https://github.com/LineageOS/mirror").unwrap(),
        "refs/heads/main",
        false,
        false,
    )
        .await?;

    let mirror_manifest = read_manifest_file(
        &mirror_fetch.path.join("default.xml"),
    )
        .await?;

    let devices = mirror_manifest
        .projects
        .iter()
        .filter_map(|project| {
            project
                .name
                .strip_prefix("LineageOS/android_device_")
                .and_then(|suffix| {
                    let fields: Vec<_> = suffix.splitn(2, "_").collect();
                    match fields.as_slice() {
                        [vendor, device] => Some((vendor.to_string(), device.to_string())),
                        _ => None,
                    }
                })
        })
        .collect();

    Ok(devices)
}

pub async fn get_repo_branches(repo: &str) -> Result<Vec<String>, GitLsRemoteError> {
    println!("`git ls-remote`-ing {repo}...");
    let output = Command::new("git")
        .arg("ls-remote")
        .arg(&format!("https://github.com/{repo}"))
        .output()
        .await
        .map_err(GitLsRemoteError::ProcessSpawn)?;

    if !output.status.success() {
        return Err(GitLsRemoteError::NonzeroExitStatus(
                output.status.code(),
                String::from_utf8_lossy(&output.stderr).to_string()
        ));
    }

    let output_str = std::str::from_utf8(&output.stdout).map_err(GitLsRemoteError::Utf8)?;
    let mut branches = vec![];
    for line in output_str.split("\n") {
        if line != "" {
            let refname = line.split("\t").nth(1).ok_or(GitLsRemoteError::Parse)?;
            if refname.starts_with("refs/heads/lineage-") {
                branches.push(refname.strip_prefix("refs/heads/").unwrap().to_string());
            }
        }
    }

    Ok(branches)
}

#[derive(Serialize, Deserialize, Debug)]
pub struct DeviceInfo {
    pub name: String,
    pub vendor: String,
    pub build_type: String,
    pub branches: BTreeMap<String, GitRepoRef>,
    pub default_branch: String,
    pub period: String,
}

#[derive(Debug, Error)]
pub enum GetDevicesError {
    #[error("error getting device defaults from hudson")]
    Hudson(#[from] FetchHudsonDevicesError),
    #[error("error getting device repo list from LineageOS mirror manifest")]
    RepoList(#[source] GetDeviceReposError),
    #[error("error fetching device repo branch list")]
    RepoBranches(#[source] GitLsRemoteError),
    #[error("device repository for `{0}` not found in LineageOS GitHub org")]
    DeviceRepoNotFound(String),
    #[error("multiple possible device repos found for device `{0}`")]
    DuplicateDeviceRepo(String),
    #[error("invalid device repo url")]
    Url(#[from] url::ParseError),
}

pub fn hudson_to_device_repo_branch(branch: &str) -> String {
    match branch {
        "lineage-21.0" => "lineage-21",
        x => x,
    }.to_string()
}

pub async fn get_devices(allowlist: &Option<Vec<String>>, blocklist: &Option<Vec<String>>) -> Result<BTreeMap<String, DeviceInfo>, GetDevicesError> {
    let mut devices = BTreeMap::new();
    let device_repos = get_device_repos()
        .await
        .map_err(GetDevicesError::RepoList)?;
    let hudson_devices = fetch_hudson_devices()
        .await
        .map_err(GetDevicesError::Hudson)?;
    let mut hudson_keys: Vec<_> = hudson_devices.keys().map(|x| x.clone()).collect();
    hudson_keys.sort();

    for name in hudson_keys.iter() {
        if allowlist.as_ref().map(|x| x.contains(name)).unwrap_or(true) && blocklist.as_ref().map(|x| !x.contains(name)).unwrap_or(true) {
            let hudson_data = hudson_devices.get(name).unwrap();
            let possible_vendors: Vec<_> = device_repos.iter().filter(|x| x.1 == *name).map(|x| x.0.clone()).collect();
            let mut found = false;
            for vendor in possible_vendors {
                let branches = get_repo_branches(&format!("LineageOS/android_device_{vendor}_{name}"))
                    .await
                    .map_err(GetDevicesError::RepoBranches)?;

                if branches.iter().any(|x| *x == hudson_to_device_repo_branch(&hudson_data.branch)) {
                    let mut branch_repos = BTreeMap::new();
                    for branch in branches {
                        branch_repos.insert(branch.clone(), GitRepoRef {
                            repo_url: Url::parse(&format!("https://github.com/LineageOS/android_device_{vendor}_{name}")).map_err(GetDevicesError::Url)?,
                            revision: format!("refs/heads/{}", hudson_to_device_repo_branch(&branch)),
                            fetch_lfs: true,
                            fetch_submodules: false,
                        });
                    }

                    if devices.contains_key(name) {
                        return Err(GetDevicesError::DuplicateDeviceRepo(name.clone()));
                    }
                    devices.insert(name.clone(), DeviceInfo {
                        name: name.clone(),
                        vendor: vendor.clone(),
                        build_type: hudson_data.build_type.clone(),
                        branches: branch_repos,
                        default_branch: hudson_data.branch.clone(),
                        period: hudson_data.period.clone(),
                    });
                    found = true;
                    break;
                }
            }
            if !found {
                return Err(GetDevicesError::DeviceRepoNotFound(name.clone()));
            }
        }
    }

    Ok(devices)
}
