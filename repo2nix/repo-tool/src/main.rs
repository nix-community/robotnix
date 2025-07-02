use std::path::{Path, PathBuf};
use std::fs;
use std::collections::BTreeMap;
use std::io::ErrorKind;
use clap::Parser;
use url::Url;
use tokio;
use serde_json;
use repo_manifest::xml::read_manifest_file;
use repo_manifest::resolver::{
    LineageDeps,
    Category,
    recursively_read_manifest_files,
    resolve_manifest,
    merge_manifests,
};
use crate::fetch::nix_prefetch_git;
use crate::lock::{
    Lockfile,
    ReadWriteLockfileError,
};
use crate::lineage_devices::DeviceInfo;
use crate::lineage_dependencies::{
    merge_lineage_devices,
    prefetch_lineage_dependencies,
    cleanup_failed_lineage_deps,
};
use crate::utils::tag_device_by_group;

mod fetch;
mod lock;
mod lineage_devices;
mod lineage_dependencies;
mod utils;

#[derive(Parser)]
enum Args {
    Fetch {
        manifest_url: String,
        lockfile_path: PathBuf,

        #[arg(long, short)]
        branch: String,

        #[arg(long, short)]
        lineage_device_file: Vec<PathBuf>,

        #[arg(long, short)]
        missing_dep_devs_file: Option<PathBuf>,

        #[arg(long)]
        muppets: bool,
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
        Args::Fetch {
            manifest_url,
            lockfile_path,
            branch,
            lineage_device_file,
            missing_dep_devs_file,
            muppets,
        } => {
            let url = Url::parse(&manifest_url).unwrap();
            let manifest_fetch = nix_prefetch_git(
                &url,
                &format!("refs/heads/{branch}"),
                false,
                false,
            ).await.unwrap();

            let mut manifest_xml = recursively_read_manifest_files(&manifest_fetch.path, Path::new("default.xml")).await.unwrap();
            if muppets {
                let muppets_fetch = nix_prefetch_git(
                    &Url::parse("https://github.com/TheMuppets/manifests").unwrap(),
                    &format!("refs/heads/{branch}"),
                    false,
                    false,
                ).await.unwrap();

                let muppets_manifest_xml = read_manifest_file(&muppets_fetch.path.join("muppets.xml")).await.unwrap();
                merge_manifests(&mut manifest_xml, &muppets_manifest_xml).unwrap();
            }
            let manifest = resolve_manifest(&manifest_xml, &url).unwrap();

            let mut lockfile = match Lockfile::read_from_file(&lockfile_path).await {
                Ok(mut lf) => {
                    lf.deactivate_all();
                    for project in manifest.projects.values() {
                        lf.add_project(project.clone()).unwrap();
                    }
                    lf
                },
                Err(ReadWriteLockfileError::IO(e)) => {
                    if e.kind() == ErrorKind::NotFound {
                        let lf = Lockfile::new(&manifest.projects, &lockfile_path);
                        lf.write().await.unwrap();
                        lf
                    } else {
                        panic!("error opening file: {e:?}");
                    }
                },
                Err(e) => panic!("{e:?}"),
            };
            tag_device_by_group(&mut lockfile, "muppets_");


            if lineage_device_file.len() > 0 {
                assert!(
                    missing_dep_devs_file.is_some(),
                    "In case of LineageOS-specific device fetching, you need to specify a file to write a list of devices with missing dependencies to with --missing-dep-devs-file"
                );
                let mut all_devices = BTreeMap::new();
                for ldf in lineage_device_file {
                    let devices: BTreeMap<String, DeviceInfo> = serde_json::from_slice(
                        &fs::read(&ldf).unwrap()
                    ).unwrap();
                    merge_lineage_devices(&mut all_devices, devices).unwrap();
                }
                prefetch_lineage_dependencies(&mut lockfile, &all_devices, &manifest, &branch).await.unwrap();

                let missing_dep_devices: Vec<_> = all_devices
                    .keys()
                    .filter(|x| lockfile.entries.iter().any(|(_, entry)| {
                        entry.project.categories.contains(&Category::DeviceSpecific(x.to_string())) && entry.project.lineage_deps == Some(LineageDeps::MissingBranch)
                    }))
                    .collect();

                println!("Devices with missing dependencies: {missing_dep_devices:?}");
                fs::write(
                    missing_dep_devs_file.unwrap(),
                    serde_json::to_vec_pretty(&missing_dep_devices).unwrap()
                ).unwrap();

                cleanup_failed_lineage_deps(&mut lockfile);
                lockfile.write().await.unwrap();
            }

            lockfile.update_all().await.unwrap();
        },
        Args::GetLineageDevices { device_metadata_file, allow, block }=> {
            let devices = lineage_devices::get_devices(&allow, &block).await.unwrap();
            fs::write(&device_metadata_file, serde_json::to_vec_pretty(&devices).unwrap()).unwrap();
        },
    }
}
