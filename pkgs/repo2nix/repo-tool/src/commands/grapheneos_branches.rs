use anyhow::{anyhow, Context, Result};
use clap::Parser;
use crate::commands::{self, CommandLike};
use log::info;
use repo_fetchers::FetchersHandle;
use repo_types::DeviceName;
use reqwest::Url;
use reqwest::header::HeaderMap;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::pin::Pin;

struct DeviceMetadata {
    tag: String,
    build_date_time: u64,
}

async fn get_device_metadata(handle: &FetchersHandle, channel: &str, device: &DeviceName) -> Result<DeviceMetadata> {
    let text = handle
        .http_get(
            &(
                Url::parse(&format!("https://releases.grapheneos.org/{}-{}", device.0, &channel)).context("failed to parse http request url")?,
                HeaderMap::new()
            ),
        )
        .await
        .context("failed to HTTP GET device metadata for channel")?;
    match &text.trim().split(' ').collect::<Vec<_>>()[..] {
        [tag, build_date_time, device_name, channel_resp] => {
            if device_name != &device.0 {
                return Err(anyhow!("API returned different device name than requested"));
            }
            if *channel_resp != channel {
                return Err(anyhow!("API returned different channel name than requested"));
            }
            let tag = tag.to_string();
            let build_date_time = build_date_time
                .parse::<u64>()
                .context("failed to parse build date time field into an int")?;

            Ok(DeviceMetadata {
                tag,
                build_date_time,
            })
        },
        _ => Err(anyhow!("API returned invalid response")),
    }
}

#[derive(Clone, Debug, Parser)]
pub struct GrapheneOSBranches {
    #[arg(short, long = "channel")]
    channels: Vec<String>,

    #[arg(short, long = "device")]
    devices: Vec<DeviceName>,

    #[arg(short = 'o', long = "out-dir")]
    lockfiles_dir: PathBuf,
}

impl CommandLike for GrapheneOSBranches {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        Box::pin(async move {
            let mut metadata = BTreeMap::new();
            let mut tags = BTreeSet::new();
            for channel in &self.channels {
                metadata.insert(channel, BTreeMap::new());
                let channel_metadata = metadata.get_mut(&channel).unwrap();
                for device in &self.devices {
                    let md = get_device_metadata(
                        &handle,
                        channel,
                        device,
                    )
                        .await
                        .context("failed to get device metadata")?;
                    tags.insert(md.tag.clone());
                    channel_metadata.insert(
                        device,
                        md,
                    );
                }
            }

            for tag in tags {
                info!("Generating lockfile for tag {tag}");
                (commands::grapheneos::GrapheneOS {
                    lockfile_path: self.lockfiles_dir.join(&tag).with_added_extension("lock"),
                    tag,
                    devices: self.devices.clone(),
                }).run(handle.clone()).await?
            }

            Ok(())
        })
    }
}
