use std::path::{Path, PathBuf};
use std::io;
use std::collections::{BTreeMap, BTreeSet};
use std::io::ErrorKind;
use clap::Parser;
use url::Url;
use tokio::{self, fs};
use serde_json;
use repo_manifest::xml::{
    read_manifest_file,
    ManifestReadFileError
};
use repo_manifest::resolver::{
    LineageDeps,
    Category,
    recursively_read_manifest_files,
    RecursivelyReadManifestFilesError,
    resolve_manifest,
    ResolveManifestError,
    merge_manifests,
};
use crate::fetch::{
    nix_prefetch_git,
    NixPrefetchGitError,
    GitLsRemoteError,
};
use crate::lock::{
    Lockset,
    ReadWriteLockfileError,
    UpdateLocksetError,
    EnsureStorePathError,
};
use crate::lineage_devices::DeviceInfo;
use crate::lineage_dependencies::{
    merge_lineage_devices,
    MergeLineageDevicesError,
    prefetch_lineage_dependencies,
    PrefetchLineageDepsError,
    cleanup_failed_lineage_deps,
};
use crate::utils::{
    tag_device_by_group,
    cleanup_broken_projects,
};
use thiserror::Error;
use main_error::MainError;

mod fetch;
mod lock;
mod lineage_devices;
mod lineage_dependencies;
mod utils;
mod graphene;

#[derive(Parser)]
enum Args {
    Fetch {
        manifest_url: String,
        lockfile_path: PathBuf,

        #[arg(long, short)]
        revision: String,

        // Interpret the `revision` argument as a git tag instead of a git branch.
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

#[derive(Debug, Error)]
enum FetchError {
    #[error("error parsing manifest URL")]
    UrlParse(#[from] url::ParseError),

    #[error("error fetching manifest")]
    ManifestFetch(#[from] NixPrefetchGitError),

    #[error("error reading manifest files")]
    ReadManifest(#[source] RecursivelyReadManifestFilesError),

    #[error("error reading Muppets manifest file")]
    ReadMuppetsManifest(#[source] ManifestReadFileError),

    #[error("error merging Muppets manifest with main manifest")]
    MergeMuppetsManifest(#[source] RecursivelyReadManifestFilesError),

    #[error("error resolving manifest remotes")]
    ResolveManifest(#[from] ResolveManifestError),

    #[error("error adding project `{0}` to lockfile")]
    AddProjectToLockset(PathBuf, #[source] UpdateLocksetError),

    #[error("error reading pre-existing lockfile")]
    ReadLockset(#[source] ReadWriteLockfileError),

    #[error("error writing lockfile")]
    WriteLockset(#[source] ReadWriteLockfileError),

    #[error("error checking whether the selected branch is present in all Muppets repositories")]
    CleanupBrokenMuppetsDevices(#[source] GitLsRemoteError),

    #[error("error reading lineage devices file")]
    ReadLineageDevicesFile(#[source] io::Error),

    #[error("error parsing lineage devices file")]
    ParseLineageDevicesFile(#[source] serde_json::Error),

    #[error("error while merging lineage devices file `{0}`")]
    MergeLineageDevices(PathBuf, #[source] MergeLineageDevicesError),

    #[error("error while prefetching lineage dependencies")]
    PrefetchLineageDeps(#[source] PrefetchLineageDepsError),

    #[error("error serializing list of broken devices")]
    SerializeBrokenDevices(#[source] serde_json::Error),

    #[error("error writing list of broken devices to file")]
    WriteBrokenDevices(#[source] io::Error),

    #[error("error updating lockfile")]
    UpdateLockset(#[source] UpdateLocksetError),
}

async fn fetch(
    manifest_url: String,
    lockfile_path: PathBuf,
    revision: String,
    tag: bool,
    lineage_device_file: Vec<PathBuf>,
    missing_dep_devs_file: Option<PathBuf>,
    muppets: bool,
) -> Result<(), FetchError> {
    if muppets || lineage_device_file.len() > 0 {
        assert!(
            missing_dep_devs_file.is_some(),
            "In case of LineageOS-specific or muppets repo fetching, you need to specify a file to write a list of devices with missing dependencies to with --missing-dep-devs-file"
        );
    }

    let url = Url::parse(&manifest_url)?;
    let git_ref = if tag {
        format!("refs/tags/{revision}")
    } else {
        format!("refs/heads/{revision}")
    };
    let manifest_fetch = nix_prefetch_git(
        &url,
        &git_ref,
        false,
        false,
    ).await?;

    let mut manifest_xml = recursively_read_manifest_files(
        &manifest_fetch.path, Path::new("default.xml")
    )
        .await
        .map_err(FetchError::ReadManifest)?;

    if muppets {
        let muppets_fetch = nix_prefetch_git(
            &Url::parse("https://github.com/TheMuppets/manifests")?,
            &format!("refs/heads/{revision}"),
            false,
            false,
        ).await?;

        let muppets_manifest_xml = read_manifest_file(&muppets_fetch.path.join("muppets.xml"))
            .await
            .map_err(FetchError::ReadMuppetsManifest)?;
        merge_manifests(&mut manifest_xml, &muppets_manifest_xml)
            .map_err(FetchError::MergeMuppetsManifest)?;
    }
    let manifest = resolve_manifest(&manifest_xml, &url)?;

    let mut lockfile = match Lockset::read_from_file(&lockfile_path).await {
        Ok(mut lf) => {
            lf.deactivate_all();
            for project in manifest.projects.values() {
                lf.add_project(project.clone())
                    .map_err(|e| FetchError::AddProjectToLockset(project.path.clone(), e))?;
            }
            lf
        },
        Err(ReadWriteLockfileError::IO(e)) => {
            if e.kind() == ErrorKind::NotFound {
                let lf = Lockset::new(&manifest.projects, &lockfile_path);
                lf.write(false)
                    .await
                    .map_err(FetchError::WriteLockset)?;
                lf
            } else {
                panic!("error opening file: {e:?}");
            }
        },
        Err(e) => return Err(FetchError::ReadLockset(e)),
    };

    let muppets_broken_devices = if muppets {
        tag_device_by_group(&mut lockfile, "muppets_");
        let broken_muppets_entries = cleanup_broken_projects(
            &mut lockfile,
            Some("muppets")
        )
            .await
            .map_err(FetchError::CleanupBrokenMuppetsDevices)?;
        let mut muppets_broken_devices = BTreeSet::new();
        for entry in broken_muppets_entries {
            for cat in entry.project.categories.iter() {
                if let Category::DeviceSpecific(device) = cat {
                    muppets_broken_devices.insert(device.clone());
                }
            }
        }
        eprintln!("Devices with broken muppets dependencies: {muppets_broken_devices:?}");
        muppets_broken_devices
    } else {
        BTreeSet::new()
    };


    if lineage_device_file.len() > 0 {
        let mut all_devices = BTreeMap::new();
        for ldf in lineage_device_file {
            let devices: BTreeMap<String, DeviceInfo> = serde_json::from_slice(
                &fs::read(&ldf)
                    .await
                    .map_err(FetchError::ReadLineageDevicesFile)?
            ).map_err(FetchError::ParseLineageDevicesFile)?;
            merge_lineage_devices(&mut all_devices, devices)
                .map_err(|e| FetchError::MergeLineageDevices(ldf, e))?;
        }
        prefetch_lineage_dependencies(
            &mut lockfile,
            &all_devices,
            &manifest,
            &revision
        )
            .await
            .map_err(FetchError::PrefetchLineageDeps)?;

        let missing_dep_devices: BTreeSet<_> = all_devices
            .keys()
            .filter(|x| lockfile.entries.iter().any(|(_, entry)| {
                entry.project.categories.contains(&Category::DeviceSpecific(x.to_string())) && entry.project.lineage_deps == Some(LineageDeps::MissingBranch)
        }))
            .cloned()
            .collect();

        println!("Devices with broken LineageOS dependencies: {missing_dep_devices:?}");
        let mut all_broken_devices = missing_dep_devices.clone();
        for device in muppets_broken_devices {
            all_broken_devices.insert(device);
        }
        fs::write(
            missing_dep_devs_file.unwrap(),
            serde_json::to_vec_pretty(&all_broken_devices)
                .map_err(FetchError::SerializeBrokenDevices)?
        )
            .await
            .map_err(FetchError::WriteBrokenDevices)?;

        cleanup_failed_lineage_deps(&mut lockfile);
        lockfile.write(false).await.map_err(FetchError::WriteLockset)?;
    }

    lockfile.update_all().await.map_err(FetchError::UpdateLockset)?;
    lockfile.write(true).await.map_err(FetchError::WriteLockset)?;

    Ok(())
}

#[derive(Debug, Error)]
enum GetLineageDevicesError {
    #[error("error fetching lineage device metadata")]
    GetDevices(#[from] lineage_devices::GetDevicesError),

    #[error("error serializing lineage device metadata into JSON")]
    Serialize(#[from] serde_json::Error),

    #[error("error writing lineage device metadata to JSON")]
    Write(#[from] io::Error),
}

async fn get_lineage_devices(device_metadata_file: PathBuf, allow: Option<Vec<String>>, block: Option<Vec<String>>) -> Result<(), GetLineageDevicesError> {
    let devices = lineage_devices::get_devices(&allow, &block)
        .await?;
    fs::write(&device_metadata_file, serde_json::to_vec_pretty(&devices)?).await?;

    Ok(())
}

#[derive(Debug, Error)]
enum GetGrapheneDevicesError {
    #[error("error reading supported devices file")]
    ReadSupportedDevices(io::Error),

    #[error("error parsing supported devices JSON")]
    ParseSupportedDevices(serde_json::Error),

    #[error("error getting device info for channel `{0}`")]
    GetChannelInfo(String, #[source] graphene::GetDeviceInfoError),

    #[error("error serializing channel info ot JSON")]
    SerializeChannelInfo(serde_json::Error),

    #[error("error writing channel info to file")]
    WriteChannelInfo(io::Error),
}

async fn get_graphene_devices(
    supported_devices_file: PathBuf,
    channel_info_file: PathBuf,
    channels: Vec<String>,
) -> Result<(), GetGrapheneDevicesError> {
    let supported_devices_json = fs::read(&supported_devices_file)
        .await
        .map_err(GetGrapheneDevicesError::ReadSupportedDevices)?;
    let supported_devices: Vec<String> = serde_json::from_slice(&supported_devices_json)
        .map_err(GetGrapheneDevicesError::ParseSupportedDevices)?;
    let mut device_info = BTreeMap::new();
    for channel in channels {
        device_info.insert(channel.clone(), graphene::get_device_info(
                &supported_devices,
                &channel
        )
            .await
            .map_err(|e| GetGrapheneDevicesError::GetChannelInfo(channel, e))?
        );
    }
    let channel_info = graphene::to_channel_info(device_info);

    fs::write(
        &channel_info_file, serde_json::to_vec_pretty(&channel_info)
        .map_err(GetGrapheneDevicesError::SerializeChannelInfo)?
    )
        .await
        .map_err(GetGrapheneDevicesError::WriteChannelInfo)?;

    Ok(())
}

#[derive(Debug, Error)]
enum GetBuildIDError {
    #[error("error reading lockfile")]
    ReadLockset(#[from] ReadWriteLockfileError),

    #[error("error ensuring that `build/make` is present in the Nix store")]
    EnsureBuildMake(#[from] EnsureStorePathError),

    #[error("error reading `core/build_id.mk`")]
    ReadBuildIdMk(io::Error),

    #[error("`build_id.mk` contains invalid UTF-8")]
    Utf8(#[from] std::str::Utf8Error),

    #[error("couldn't parse `build_id.mk`")]
    ParseBuildIdMk,

    #[error("error serializing build IDs to JSON")]
    SerializeBuildIDs(#[from] serde_json::Error),

    #[error("error writing build IDs to file")]
    WriteBuildIDs(io::Error),
}

async fn get_build_ids(out_file: PathBuf, lockfiles: Vec<PathBuf>) -> Result<(), GetBuildIDError> {
    let mut build_ids: BTreeMap<PathBuf, String> = BTreeMap::new();
    for lockfile_path in lockfiles.iter() {
        let lockfile = Lockset::read_from_file(lockfile_path).await?;
        let build_make_path = Path::new("build/make");
        let platform_build_path = &lockfile.entries
            .get(build_make_path)
            .expect("path `build/make` not found in lockfile {lockfile_path}")
            .lock
            .as_ref()
            .expect("path `build/make` is not locked yet in lockfile {lockfile_path}")
            .path;

        lockfile.ensure_store_path(build_make_path)
            .await?;

        let build_id_mk_text = fs::read(
            platform_build_path.join("core/build_id.mk")
        )
            .await
            .map_err(GetBuildIDError::ReadBuildIdMk)?;
        let build_id_mk_text = std::str::from_utf8(&build_id_mk_text)?;
        let lines: Vec<String> = build_id_mk_text
            .split('\n')
            .filter_map(|x| x.strip_prefix("BUILD_ID=").map(|x| x.to_string()))
            .collect();

        match lines.as_slice() {
            [ build_id, ] => {
                build_ids.insert(lockfile_path.clone(), build_id.clone());
            },
            _ => return Err(GetBuildIDError::ParseBuildIdMk),
        }
    }

    fs::write(&out_file, serde_json::to_vec_pretty(&build_ids)?)
        .await
        .map_err(GetBuildIDError::WriteBuildIDs)?;

    Ok(())
}

#[derive(Debug, Error)]
enum EnsureStorePathsError {
    #[error("error reading lockfile")]
    ReadLockset(#[from] ReadWriteLockfileError),

    #[error("error ensuring that `{0}` is present in the Nix store")]
    EnsurePath(#[from] EnsureStorePathError),
}

async fn ensure_store_paths(lockfile_path: PathBuf, store_paths: Option<Vec<PathBuf>>) -> Result<(), EnsureStorePathsError> {
    let lockfile = Lockset::read_from_file(&lockfile_path).await?;
    let paths = match store_paths {
        Some(paths) => paths,
        None => lockfile.entries.keys().cloned().collect(),
    };
    for path in paths {
        lockfile.ensure_store_path(&path).await?;
    }

    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), MainError> {
    let args = Args::parse();

    match args {
        Args::Fetch {
            manifest_url,
            lockfile_path,
            revision,
            tag,
            lineage_device_file,
            missing_dep_devs_file,
            muppets,
        } => {
            fetch(
                manifest_url,
                lockfile_path,
                revision,
                tag,
                lineage_device_file,
                missing_dep_devs_file,
                muppets,
            )
                .await?;
        },

        Args::GetLineageDevices { device_metadata_file, allow, block } => {
            get_lineage_devices(
                device_metadata_file,
                allow,
                block
            )
                .await?;
        },

        Args::GetGrapheneDevices { supported_devices_file, channel_info_file, channels } => {
            get_graphene_devices(
                supported_devices_file,
                channel_info_file,
                channels
            )
                .await?;
        },

        Args::GetBuildID { out_file, lockfiles } => {
            get_build_ids(
                out_file,
                lockfiles
            )
                .await?;
        },

        Args::EnsureStorePaths { lockfile_path, store_paths } => {
            ensure_store_paths(lockfile_path, store_paths).await?;
        },
    }

    Ok(())
}
