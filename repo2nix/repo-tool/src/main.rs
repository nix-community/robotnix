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
use crate::utils::{
    tag_device_by_group,
    cleanup_broken_projects,
};
use main_error::MainError;

mod fetch;
mod lock;
mod lineage_devices;
mod lineage_dependencies;
mod utils;
mod graphene;
mod graphene_vendor;

#[derive(Parser)]
enum Args {
    Fetch {
        manifest_url: String,
        lockfile_path: PathBuf,

        #[arg(long, short)]
        branch: String,

        // Interpret the `branch` argument as a git tag instead of a git branch.
        #[arg(long, short)]
        tag: bool,

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
    GetGrapheneDevices {
        supported_devices_file: PathBuf,
        channel_info_file: PathBuf,

        #[arg(long, short)]
        channels: Vec<String>,
    },
    GetGrapheneVendorImgMetadata {
        adevtool_path: PathBuf,
        vendor_img_metadata_path: PathBuf,
        devices: Vec<String>,
    },
    GetBuildID {
        out_file: PathBuf,
        lockfiles: Vec<PathBuf>,
    },
    EnsureStorePaths {
        lockfile_path: PathBuf,
        store_paths: Option<Vec<PathBuf>>,
    },
}

#[tokio::main]
async fn main() -> Result<(), MainError> {
    let args = Args::parse();

    match args {
        Args::Fetch {
            manifest_url,
            lockfile_path,
            branch,
            tag,
            lineage_device_file,
            missing_dep_devs_file,
            muppets,
        } => {
            if muppets || lineage_device_file.len() > 0 {
                assert!(
                    missing_dep_devs_file.is_some(),
                    "In case of LineageOS-specific or muppets repo fetching, you need to specify a file to write a list of devices with missing dependencies to with --missing-dep-devs-file"
                );
            }

            let url = Url::parse(&manifest_url)?;
            let git_ref = if tag {
                format!("refs/tags/{branch}")
            } else {
                format!("refs/heads/{branch}")
            };
            let manifest_fetch = nix_prefetch_git(
                &url,
                &git_ref,
                false,
                false,
            ).await?;

            let mut manifest_xml = recursively_read_manifest_files(&manifest_fetch.path, Path::new("default.xml")).await?;
            if muppets {
                let muppets_fetch = nix_prefetch_git(
                    &Url::parse("https://github.com/TheMuppets/manifests")?,
                    &format!("refs/heads/{branch}"),
                    false,
                    false,
                ).await?;

                let muppets_manifest_xml = read_manifest_file(&muppets_fetch.path.join("muppets.xml")).await?;
                merge_manifests(&mut manifest_xml, &muppets_manifest_xml)?;
            }
            let manifest = resolve_manifest(&manifest_xml, &url)?;

            let mut lockfile = match Lockfile::read_from_file(&lockfile_path).await {
                Ok(mut lf) => {
                    lf.deactivate_all();
                    for project in manifest.projects.values() {
                        lf.add_project(project.clone())?;
                    }
                    lf
                },
                Err(ReadWriteLockfileError::IO(e)) => {
                    if e.kind() == ErrorKind::NotFound {
                        let lf = Lockfile::new(&manifest.projects, &lockfile_path);
                        lf.write().await?;
                        lf
                    } else {
                        panic!("error opening file: {e:?}");
                    }
                },
                Err(e) => panic!("{e:?}"),
            };

            let muppets_broken_devices = if muppets {
                tag_device_by_group(&mut lockfile, "muppets_");
                let broken_muppets_entries = cleanup_broken_projects(
                    &mut lockfile,
                    Some("muppets")
                ).await?;
                let mut muppets_broken_devices = vec![];
                for entry in broken_muppets_entries {
                    for cat in entry.project.categories {
                        if let Category::DeviceSpecific(device) = cat {
                            if !muppets_broken_devices.contains(&device) {
                                muppets_broken_devices.push(device);
                            }
                        }
                    }
                }
                eprintln!("Devices with broken muppets dependencies: {muppets_broken_devices:?}");
                muppets_broken_devices
            } else {
                vec![]
            };


            if lineage_device_file.len() > 0 {
                let mut all_devices = BTreeMap::new();
                for ldf in lineage_device_file {
                    let devices: BTreeMap<String, DeviceInfo> = serde_json::from_slice(
                        &fs::read(&ldf)?
                    )?;
                    merge_lineage_devices(&mut all_devices, devices)?;
                }
                prefetch_lineage_dependencies(&mut lockfile, &all_devices, &manifest, &branch).await?;

                let missing_dep_devices: Vec<_> = all_devices
                    .keys()
                    .filter(|x| lockfile.entries.iter().any(|(_, entry)| {
                        entry.project.categories.contains(&Category::DeviceSpecific(x.to_string())) && entry.project.lineage_deps == Some(LineageDeps::MissingBranch)
                    }))
                    .cloned()
                    .collect();

                println!("Devices with broken LineageOS dependencies: {missing_dep_devices:?}");
                let mut all_broken_devices = missing_dep_devices.clone();
                for device in muppets_broken_devices {
                    if !all_broken_devices.contains(&device) {
                        all_broken_devices.push(device);
                    }
                }
                fs::write(
                    missing_dep_devs_file.unwrap(),
                    serde_json::to_vec_pretty(&all_broken_devices)?
                )?;

                cleanup_failed_lineage_deps(&mut lockfile);
                lockfile.write().await?;
            }

            lockfile.update_all().await?;
        },

        Args::GetLineageDevices { device_metadata_file, allow, block } => {
            let devices = lineage_devices::get_devices(&allow, &block).await?;
            fs::write(&device_metadata_file, serde_json::to_vec_pretty(&devices)?)?;
        },

        Args::GetGrapheneDevices { supported_devices_file, channel_info_file, channels } => {
            let supported_devices_json = fs::read(&supported_devices_file)?;
            let supported_devices: Vec<String> = serde_json::from_slice(&supported_devices_json)?;
            let mut device_info = BTreeMap::new();
            for channel in channels {
                device_info.insert(channel.clone(), graphene::get_device_info(&supported_devices, &channel).await?);
            }
            let channel_info = graphene::to_channel_info(device_info);

            fs::write(&channel_info_file, serde_json::to_vec_pretty(&channel_info)?)?;
        },

        Args::GetGrapheneVendorImgMetadata { adevtool_path, devices, vendor_img_metadata_path } => {
            let metadata = graphene_vendor::get_vendor_img_metadata(&adevtool_path, &devices).await?;
            fs::write(&vendor_img_metadata_path, serde_json::to_vec_pretty(&metadata)?)?;

        },

        Args::GetBuildID { out_file, lockfiles } => {
            let mut build_ids: BTreeMap<PathBuf, String> = BTreeMap::new();
            for lockfile_path in lockfiles.iter() {
                let lockfile = Lockfile::read_from_file(lockfile_path).await?;
                let build_make_path = Path::new("build/make");
                let platform_build_path = &lockfile.entries
                    .get(build_make_path)
                    .expect("path `build/make` not found in lockfile {lockfile_path}")
                    .lock
                    .as_ref()
                    .expect("path `build/make` is not locked yet in lockfile {lockfile_path}")
                    .path;

                lockfile.ensure_store_path(build_make_path).await?;

                let build_id_mk_text = fs::read(
                    platform_build_path.join("core/build_id.mk")
                )?;
                let build_id_mk_text = std::str::from_utf8(&build_id_mk_text)?;
                let lines: Vec<String> = build_id_mk_text
                    .split('\n')
                    .filter_map(|x| x.strip_prefix("BUILD_ID=").map(|x| x.to_string()))
                    .collect();

                match lines.as_slice() {
                    [ build_id, ] => {
                        build_ids.insert(lockfile_path.clone(), build_id.clone());
                    },
                    _ => panic!("Failed to parse build_id.mk"),
                }
            }

            fs::write(&out_file, serde_json::to_vec_pretty(&build_ids)?)?;
        },

        Args::EnsureStorePaths { lockfile_path, store_paths } => {
            let lockfile = Lockfile::read_from_file(&lockfile_path).await?;
            let mut paths = match store_paths {
                Some(paths) => paths,
                None => lockfile.entries.keys().cloned().collect(),
            };
            for path in paths {
                lockfile.ensure_store_path(&path).await?;
            }
        },
    }

    Ok(())
}
