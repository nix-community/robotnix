use std::path::{Path, PathBuf};
use std::fs;
use std::collections::BTreeMap;
use std::io::ErrorKind;
use clap::Parser;
use url::Url;
use tokio;
use serde_json;
use repo_manifest::resolver::{
    recursively_read_manifest_files,
    resolve_manifest,
};
use crate::fetch::nix_prefetch_git;
use crate::lock::{
    Lockfile,
    ReadWriteLockfileError,
};
use crate::lineage_devices::DeviceInfo;
use crate::lineage_dependencies::{
    add_lineage_devices,
    prefetch_lineage_dependencies,
};

mod fetch;
mod lock;
mod lineage_devices;
mod lineage_dependencies;

#[derive(Parser)]
enum Args {
    Fetch {
        manifest_url: String,
        lockfile_path: PathBuf,

        #[arg(long, short)]
        branch: String,

        #[arg(long, short)]
        lineage_device_file: Vec<PathBuf>,
    },
    GetLineageDevices {
        device_metadata_file: PathBuf,

        /// Only include these device(s).
        #[arg(long, short)]
        allow: Option<Vec<String>>,

        /// Do not include these device(s).
        #[arg(long, short)]
        block: Option<Vec<String>>,
    },
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    match args {
        Args::Fetch { manifest_url, lockfile_path, branch, lineage_device_file } => {
            let url = Url::parse(&manifest_url).unwrap();
            let manifest_fetch = nix_prefetch_git(
                &url,
                &format!("refs/heads/{branch}"),
                false,
                false,
            ).await.unwrap();

            let manifest_xml = recursively_read_manifest_files(&manifest_fetch.path, Path::new("default.xml")).await.unwrap();
            let mut manifest = resolve_manifest(&manifest_xml, &url).unwrap();

            for ldf in lineage_device_file {
                let devices: BTreeMap<String, DeviceInfo> = serde_json::from_slice(
                    &fs::read(&ldf).unwrap()
                ).unwrap();
                add_lineage_devices(&mut manifest, &devices, &branch);
            }
            prefetch_lineage_dependencies(&mut manifest).await.unwrap();


            let mut lockfile = match Lockfile::read_from_file(&lockfile_path).await {
                Ok(mut lf) => {
                    lf.set_projects(&manifest.projects);
                    lf
                },
                Err(ReadWriteLockfileError::IO(e)) => {
                    if e.kind() == ErrorKind::NotFound {
                        let lf = Lockfile::new(&manifest.projects);
                        lf.write_to_file(&lockfile_path).await.unwrap();
                        lf
                    } else {
                        panic!("error opening file: {e:?}");
                    }
                },
                Err(e) => panic!("{e:?}"),
            };

            lockfile.update(Some(&lockfile_path)).await.unwrap();
        },
        Args::GetLineageDevices { device_metadata_file, allow, block }=> {
            let devices = lineage_devices::get_devices(&allow, &block).await.unwrap();
            fs::write(&device_metadata_file, serde_json::to_vec_pretty(&devices).unwrap()).unwrap();
        },
    }
}
