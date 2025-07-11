use std::collections::{BTreeMap, BTreeSet};
use std::str::FromStr;
use serde::Serialize;
use reqwest;
use thiserror::Error;

#[derive(Debug, Serialize)]
pub struct DeviceInfo {
    pub git_tag: String,
    pub build_time: u64,
}

#[derive(Debug, Serialize)]
pub struct ChannelInfo {
    pub device_info: BTreeMap<String, BTreeMap<String, DeviceInfo>>,
    pub channels: BTreeSet<String>,
    pub git_tags: BTreeSet<String>,
}

#[derive(Debug, Error)]
pub enum GetDeviceInfoError {
    #[error("error fetching release info")]
    HTTP(#[from] reqwest::Error),
    #[error("error parsing response")]
    Parse(String),
}

pub async fn get_device_info(devices: &[String], channel: &str) -> Result<BTreeMap<String, DeviceInfo>, GetDeviceInfoError> {
    let mut device_info = BTreeMap::new();
    for device in devices.iter() {
        eprintln!("Fetching device info for {device}...");
        let text = reqwest::get(&format!(
                "https://releases.grapheneos.org/{}-{}",
                device,
                channel,
            ))
            .await
            .map_err(GetDeviceInfoError::HTTP)?
            .text()
            .await
            .map_err(GetDeviceInfoError::HTTP)?;

        match text.trim_end().split(" ").collect::<Vec<_>>().as_slice() {
            [git_tag, build_time, _, _] => {
                let build_time = u64::from_str(build_time)
                    .map_err(|_| GetDeviceInfoError::Parse(text.clone()))?;

                device_info.insert(device.clone(), DeviceInfo {
                    git_tag: git_tag.to_string(),
                    build_time: build_time,
                });
            },
            _ => return Err(GetDeviceInfoError::Parse(text.clone())),
        }
    }

    Ok(device_info)
}

pub fn to_channel_info(device_info: BTreeMap<String, BTreeMap<String, DeviceInfo>>) -> ChannelInfo {
    let git_tags: BTreeSet<String> = device_info
        .iter()
        .map(|(_, x)|
            x
            .iter()
            .map(|(_, y)| y.git_tag.clone())
        )
        .flatten()
        .collect();

    ChannelInfo {
        git_tags: git_tags,
        channels: device_info.keys().cloned().collect(),
        device_info: device_info,
    }
}
