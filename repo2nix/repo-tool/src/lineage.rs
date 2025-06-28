use std::collections::{BTreeMap, HashMap};
use std::io;
use std::str;
use serde::{Serialize, Deserialize};
use url::Url;
use tokio::fs;
use tokio::process::Command;
use reqwest::{self, StatusCode};
use serde_json::{self, Value};
use thiserror::Error;
use repo_manifest::resolver::GitRepoRef;
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
    ).await.map_err(FetchHudsonDevicesError::Fetch)?;

    let bytes = fs::read(&hudson_fetch.path.join("lineage-build-targets"))
        .await
        .map_err(FetchHudsonDevicesError::IO)?;

    let text = str::from_utf8(&bytes)
        .map_err(FetchHudsonDevicesError::Utf8)?;

    let mut devices = HashMap::new();
    for line in text.split("\n") {
        let line = line.trim_end();
        if line != "" && !line.starts_with("#") {
            let mut fields = line.split(" ");
            let name = fields.next().ok_or(FetchHudsonDevicesError::ParseLine(line.to_string()))?;
            let build_type = fields.next().ok_or(FetchHudsonDevicesError::ParseLine(line.to_string()))?;
            let branch = fields.next().ok_or(FetchHudsonDevicesError::ParseLine(line.to_string()))?;
            let period = fields.next().ok_or(FetchHudsonDevicesError::ParseLine(line.to_string()))?;
            devices.insert(name.to_string(), HudsonDeviceInfo {
                build_type: build_type.to_string(),
                branch: branch.to_string(),
                period: period.to_string(),
            });
        }
    }

    Ok(devices)
}

#[derive(Debug, Error)]
pub enum GithubAPIError {
    #[error("error calling GitHub API")]
    HTTP(#[from] reqwest::Error),
    #[error("GitHub API returned non-2xx status code `{0}`, body {1}")]
    UnsuccessfulRequest(StatusCode, String),
    #[error("error parsing JSON")]
    Parse(#[from] serde_json::Error),
    #[error("invalid API response")]
    InvalidResponse,
}

pub async fn list_device_repos(client: &mut reqwest::Client) -> Result<Vec<(String, String)>, GithubAPIError> {
    let mut devices = vec![];
    let mut page = 1;
    loop {
        println!("Fetching LineageOS repo list (page {})...", &page);
        let res = client
            .get(format!("https://api.github.com/orgs/LineageOS/repos?per_page=100&page={}", page))
            .header("User-Agent", "repo2nix (reqwest)")
            .send()
            .await
            .map_err(GithubAPIError::HTTP)?;

        let status = res.status();
        let body = res.bytes().await.map_err(GithubAPIError::HTTP)?;

        if !status.is_success() {
            return Err(GithubAPIError::UnsuccessfulRequest(status, String::from_utf8_lossy(&body).to_string()));
        }
        
        let data: Value = serde_json::from_slice(&body)
            .map_err(GithubAPIError::Parse)?;

        match data {
            Value::Array(entries) => {
                if entries.len() == 0 {
                    break;
                }

                for entry in entries {
                    let repo_name = match entry {
                        Value::Object(vals) => {
                            match vals.get("name") {
                                Some(Value::String(name)) => name.clone(),
                                _ => return Err(GithubAPIError::InvalidResponse),
                            }
                        },
                        _ => return Err(GithubAPIError::InvalidResponse),
                    };
                    if repo_name.starts_with("android_device") {
                        let mut fields = repo_name.splitn(4, "_").skip(2);
                        let vendor = match fields.next() {
                            Some(s) => s,
                            None => continue,
                        };
                        let product = match fields.next() {
                            Some(s) => s,
                            None => continue,
                        };

                        devices.push((vendor.to_string(), product.to_string()));
                    }
                }

                page += 1;
            },
            _ => return Err(GithubAPIError::InvalidResponse),
        }
    }

    Ok(devices)
}

pub async fn get_repo_branches(client: &mut reqwest::Client, repo: &str) -> Result<Vec<String>, GitLsRemoteError> {
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
    #[error("error getting device repo list from GitHub API")]
    RepoList(#[source] GithubAPIError),
    #[error("error fetching device repo branch list from GitHub API")]
    RepoBranches(#[source] GitLsRemoteError),
    #[error("device repository for `{0}` not found in LineageOS GitHub org")]
    DeviceRepoNotFound(String),
    #[error("multiple possible device repos found for device `{0}`: `{1:?}`")]
    DuplicateDeviceRepo(String, Vec<String>),
    #[error("hudson-provided default branch `{0}` not present in device repo for `{1}`")]
    DefaultBranchNotFound(String, String),
    #[error("invalid device repo url")]
    Url(#[from] url::ParseError),
}

fn hudson_to_device_repo_branch(branch: &str) -> String {
    match branch {
        "lineage-21.0" => "lineage-21",
        x => x,
    }.to_string()
}

pub async fn get_devices() -> Result<BTreeMap<String, DeviceInfo>, GetDevicesError> {
    let mut client = reqwest::Client::new();
    let mut devices = BTreeMap::new();
    let device_repos = list_device_repos(&mut client, )
        .await
        .map_err(GetDevicesError::RepoList)?;
    let hudson_devices = fetch_hudson_devices()
        .await
        .map_err(GetDevicesError::Hudson)?;
    let mut hudson_keys: Vec<_> = hudson_devices.keys().map(|x| x.clone()).collect();
    hudson_keys.sort();

    for name in hudson_keys.iter() {
        let hudson_data = hudson_devices.get(name).unwrap();
        let possible_vendors: Vec<_> = device_repos.iter().filter(|x| x.1 == *name).map(|x| x.0.clone()).collect();
        for vendor in possible_vendors {
            let branches = get_repo_branches(&mut client, &format!("LineageOS/android_device_{vendor}_{name}"))
                .await
                .map_err(GetDevicesError::RepoBranches)?;

            if branches.iter().any(|x| *x == hudson_to_device_repo_branch(&hudson_data.branch)) {
                let mut branch_repos = BTreeMap::new();
                for branch in branches {
                    branch_repos.insert(branch.clone(), GitRepoRef {
                        repo_url: Url::parse(&format!("https://github.com/LineageOS/android_device_{vendor}_{name}")).map_err(GetDevicesError::Url)?,
                        revision: format!("refs/heads/{}", hudson_to_device_repo_branch(&branch)),
                        fetch_lfs: false,
                        fetch_submodules: false,
                    });
                }

                devices.insert(name.clone(), DeviceInfo {
                    name: name.clone(),
                    vendor: vendor.clone(),
                    build_type: hudson_data.build_type.clone(),
                    branches: branch_repos,
                    default_branch: hudson_data.branch.clone(),
                    period: hudson_data.period.clone(),
                });
                break;
            }
        }
    }

    Ok(devices)
}
