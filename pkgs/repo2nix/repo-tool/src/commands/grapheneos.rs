use anyhow::{Context, Result};
use clap::Parser;
use crate::prefetch_projects;
use nix::fcntl::{openat, OFlag};
use nix::sys::stat::Mode;
use nix_compat::nixhash::NixHash;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestState};
use repo_types::{DeviceName, GitRef, GitRefOrCommitId, RepoUrl, lockfile};
use serde::{Serialize, Deserialize};
use std::collections::BTreeMap;
use std::fs::{File, OpenOptions};
use std::io::Read;
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use super::CommandLike;

async fn prefetch_yarn(handle: &FetchersHandle, project: &lockfile::Project) -> Result<NixHash> {
    let adevtool_fd = handle.source_dir_fd(
        &(
            project.src.repo_url.clone(),
            project.src.commit_id.clone(),
            project.src.hash.clone(),
        )
    )
        .await
        .context("failed to open source dir")?;

    let yarn_lockfile_fd = openat(
        adevtool_fd.as_fd(),
        Path::new("yarn.lock"),
        OFlag::O_RDONLY | OFlag::O_CLOEXEC,
        Mode::empty(),
    )
        .context("failed to open yarn.lock file in source dir")?;

    let mut yarn_lockfile = String::new();
    File::from(yarn_lockfile_fd)
        .read_to_string(&mut yarn_lockfile)
        .context("failed to read yarn lockfile")?;

    let yarn_hash = handle.reproducible_command(
        &(
            [
                "prefetch-yarn-deps",
                "/dev/stdin",
            ]
                .iter()
                .map(|x| x.to_string())
                .collect(),
            yarn_lockfile,
        )
    )
        .await
        .context("failed to execute prefetch-yarn-deps")?;

    let yarn_hash = NixHash::from_nix_nixbase32(
        &format!("sha256:{}", yarn_hash.trim())
    )
        .context("failed to parse nixbase32 sha256 hash outputted by prefetch-yarn-deps")?;

    Ok(yarn_hash)
}

// ideally, this would be done 100% within nix with dyn drvs...
// warning: extremely cursed shit to follow
async fn get_vendor_image_metadata(
    handle: &FetchersHandle,
    adevtool_project: &lockfile::Project,
    tag: &str,
    adevtool_yarn_hash: &NixHash,
    devices: &Vec<String>
) -> Result<BTreeMap<DeviceName, Vec<VendorImage>>> {
    let nix_src = format!("
        let
          url = \"{}\";
          rev = \"{}\";
          tag = \"{}\";
          hash = \"{}\";
          yarnHash = \"{}\";
          devices = \"{}\";
          pkgs = import <nixpkgs> {{ }};
          lib = pkgs.lib;
          src = pkgs.fetchgit {{
            inherit url rev hash;
          }};
          yarnOfflineCache = pkgs.fetchYarnDeps {{
            yarnLock = \"${{src}}/yarn.lock\";
            hash = yarnHash;
          }};
          adevtool =
            pkgs.runCommand \"adevtool\"
              {{
                nativeBuildInputs = with pkgs; [
                  yarnConfigHook
                ];
              }}
              ''
                mkdir -p $out/vendor
                cp -r ${{src}} $out/vendor/adevtool
                chmod -R u+w $out
                cd $out/vendor/adevtool
                cat <<EOF | patch -p1
                diff --git a/src/frontend/source.ts b/src/frontend/source.ts
                index a5c8c1d1..153cc702 100644
                --- a/src/frontend/source.ts
                +++ b/src/frontend/source.ts
                @@ -71,6 +71,24 @@ export async function prepareDeviceImages(
                     }}
                   }}

                +  let imageMetadata = []
                +  for (let images of imagesMap.values()) {{
                +    let imageToUnpack: DeviceImage | null = null
                +    if (images.factoryImage !== undefined && !images.factoryImage.isGrapheneOS) {{
                +      imageToUnpack = images.factoryImage
                +    }} else if (images.otaImage !== undefined) {{
                +      imageToUnpack = images.otaImage
                +    }}
                +
                +    imageMetadata.push({{
                +      fileName: imageToUnpack.fileName,
                +      url: imageToUnpack.url,
                +      sha256: imageToUnpack.sha256,
                +    }})
                +  }}
                +  console.log(JSON.stringify(imageMetadata))
                +  process.exit(0)
                +
                   let jobs = Array.from(imagesMap.values()).map(images =>
                     (async () => {{
                       let imageToUnpack: DeviceImage | null = null
                EOF
                cat <<EOF | patch -p1
                diff --git a/bin/run b/bin/run
                index c7758340..94ab7723 100755
                --- a/bin/run
                +++ b/bin/run
                @@ -32,16 +32,6 @@ if (!validCwd) {{
                   process.exit(1)
                 }}

                -let extraPathDirs = [cwd + '/prebuilts/build-tools/path/linux-x86', cwd + '/prebuilts/jdk/jdk21/linux-x86/bin']
                -for (let dir of extraPathDirs) {{
                -  let stat = statSync(dir, {{ throwIfNoEntry: false }})
                -  if (stat === undefined || !stat.isDirectory()) {{
                -    throw new Error('missing prebuilts dir: ' + dir)
                -  }}
                -}}
                -
                -process.env.PATH = extraPathDirs.join(':') + ':' + process.env.PATH
                -
                 process.env.UV_THREADPOOL_SIZE = require('os').cpus().length.toString()

                 void (async () => {{
                EOF
                yarnOfflineCache=${{yarnOfflineCache}}
                yarnConfigHook
                sed -i \"s|#!/usr/bin/env node|#!${{lib.getExe pkgs.nodejs}}|g\" bin/run
              '';
          vendor-imgs = pkgs.runCommand \"adevtool-vendor-imgs\" {{
            nativeBuildInputs = [ pkgs.nodejs pkgs.jq ];
          }} ''
            cd ${{adevtool}}
            mkdir $out
            echo \"{{}}\" > $out/vendor_imgs.json
            for device in ${{devices}}; do
              vendor/adevtool/bin/run generate-all -d $device | jq --arg device $device --slurpfile stdin /dev/stdin '. + {{$device: $stdin[0]}}' $out/vendor_imgs.json > $out/vendor_imgs.json_
              mv $out/vendor_imgs.json_ $out/vendor_imgs.json
            done
          '';
        in
          vendor-imgs
        ",
        adevtool_project.src.repo_url.0,
        adevtool_project.src.commit_id,
        tag,
        adevtool_project.src.hash.to_sri_string(),
        adevtool_yarn_hash,
        devices.join(" "),
    );

    let vendor_imgs = handle.reproducible_command(
        &(
            [
                "bash",
                "-c",
                "set -euo pipefail; cat $(nix build --file - --print-out-paths --no-link)/vendor_imgs.json",
            ]
                .into_iter()
                .map(|x| x.to_string())
                .collect(),
            nix_src,
        ),
    )
        .await
        .context("failed to execute vendor image metadata nix build")?;

    serde_json::from_str(&vendor_imgs)
        .context("failed to deserialize output of vendor image metadata build")
}

#[derive(Serialize, Deserialize)]
struct VendorImage {
    #[serde(rename = "fileName")]
    filename: String,
    url: String,
    #[serde(rename = "sha256")]
    hash: String,
}

#[derive(Debug, Clone, Parser)]
pub struct GrapheneOS {
    #[arg(short, long)]
    tag: String,

    #[arg(short, long)]
    devices: Vec<String>,

    #[arg(short = 'o', long = "output")]
    lockfile_path: PathBuf,
}

impl CommandLike for GrapheneOS {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        Box::pin(async move {
            let manifest_url = RepoUrl("https://github.com/GrapheneOS/platform_manifest".to_string());
            let (_, _, manifest_fd) = handle
                .source_dir_by_ref_or_commit_id(
                    &manifest_url,
                    &GitRefOrCommitId::GitRef(GitRef(format!("refs/tags/{}", self.tag))),
                )
                .await
                .context("failed to fetch manifest repo")?;

            let instructions =
                repo_manifest::recursively_read_manifest(manifest_fd.as_fd(), Path::new("default.xml"))
                .context("failed to recursively read manifest")?;

            let mut manifest = ManifestState::new(manifest_url.clone());
            for instruction in instructions {
                instruction
                    .execute_on(&mut manifest)
                    .context("failed to apply instruction to manifest")?;
            }

            let projects = prefetch_projects(&manifest, &handle)
                .await
                .context("failed to prefetch projects")?;

            #[derive(Serialize)]
            struct GrapheneLockfile {
                projects: BTreeMap<PathBuf, lockfile::Project>,
                #[serde(with = "repo_types::custom_serde::nix_hash")]
                adevtool_yarn_hash: NixHash,
                vendor_images: BTreeMap<DeviceName, Vec<VendorImage>>,
            }

            let adevtool_project = projects
                .get(Path::new("vendor/adevtool"))
                .context("project `vendor/adevtool` not present in manifest")?;

            let adevtool_yarn_hash = prefetch_yarn(
                &handle,
                adevtool_project,
            )
                .await
                .context("failed to prefetch adevtool yarn hash")?;

            let vendor_images = get_vendor_image_metadata(
                &handle,
                adevtool_project,
                &self.tag,
                &adevtool_yarn_hash,
                &self.devices,
            )
                .await
                .context("failed to get vendor image metadata")?;

            let lockfile = GrapheneLockfile {
                projects,
                adevtool_yarn_hash,
                vendor_images,
            };

            let file = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&self.lockfile_path)
                .context("failed to open lockfile for writing")?;

            serde_json::to_writer_pretty(file, &lockfile)
                .context("failed to serialize lockfile")?;

            Ok(())
        })
    }
}
