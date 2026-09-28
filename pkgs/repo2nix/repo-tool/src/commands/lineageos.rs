use super::CommandLike;
use crate::{PrefetchProjectError, prefetch_project, prefetch_projects};
use anyhow::{Context, Result, anyhow};
use clap::Parser;
use nix::errno::Errno;
use nix::fcntl::{OFlag, openat};
use nix::sys::stat::Mode;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ExecuteOnState, ManifestConfigState, ManifestState};
use repo_manifest::xml::{GitRepoRevision, Include, Instruction, Project, RelativeUrl, RemoteName};
use repo_types::lockfile;
use repo_types::{DeviceName, GitRef, GitRefOrCommitId, Groups, RepoUrl};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader};
use std::os::fd::{AsFd, BorrowedFd};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use tokio::task::JoinSet;

#[derive(Deserialize)]
#[serde(untagged)] // untagged instead of tagged, since the JSON `type` field can be missing
enum Dependency {
    #[serde(rename = "project")]
    Project {
        #[serde(rename = "target_path")]
        source_tree_path: PathBuf,

        #[serde(rename = "repository")]
        relative_url: RelativeUrl,

        remote: Option<RemoteName>,

        #[serde(rename = "branch")]
        revision: Option<GitRepoRevision>,
    },
    #[serde(rename = "kernel")]
    Kernel { version: String },
}

enum ResolvedDependency {
    Project(Project),
    Include(Include),
}

impl Dependency {
    // This function replicates the lineage.dependencies parsing logic spread out in the
    // roomservice.py functions `fetch_dependencies` and `add_to_manifest`:
    // https://github.com/LineageOS/android_vendor_lineage/blob/d747e9abec858434d4967eb5fa9cd3e87c5cc7b0/build/tools/roomservice.py#L178
    fn resolve(self, config: &ManifestConfigState) -> Result<ResolvedDependency> {
        Ok(match self {
            Dependency::Project {
                source_tree_path,
                relative_url,
                remote,
                revision,
            } => {
                ResolvedDependency::Project(Project {
                    // techdebt behaviour which I have to replicate.
                    // yes it breaks once you add in remotes other than github and the aosp-* ones,
                    // no i cant do anything about it
                    relative_url: if let Some(ref remote) = remote
                        && remote.0.starts_with("aosp-")
                    {
                        relative_url
                    } else {
                        RelativeUrl(format!("LineageOS/{}", relative_url.0))
                    },
                    source_tree_path: Some(source_tree_path),
                    revision: match revision {
                        Some(revision) => Some(revision),
                        None => {
                            if let Some(RemoteName(ref remote_name)) = remote
                                && remote_name == "github"
                            {
                                // yes, roomservice.py looks up the default revision of the default
                                // remote, and not of the `github` remote (i.e. assumes that
                                // `github` always is the default remote)
                                Some(GitRepoRevision::from_git_ref_or_commit_id(
                                    config
                                        .default_remote
                                        .as_ref()
                                        .ok_or(anyhow!("manifest is missing <default /> tag"))?
                                        .1
                                        .as_ref()
                                        .ok_or(anyhow!(
                                            "<default /> tag in manifest is missing revision attr"
                                        ))?
                                        .clone(),
                                ))
                            } else {
                                None
                            }
                        }
                    },
                    remote: Some(remote.unwrap_or(RemoteName("github".to_string()))),
                    groups: Groups(BTreeSet::new()),
                    linkfiles: vec![],
                    copyfiles: vec![],
                })
            }
            Dependency::Kernel { version } => ResolvedDependency::Include(Include {
                path: PathBuf::from(format!("snippets/kernel-{version}.xml")),
            }),
        })
    }
}

async fn get_all_devices(
    branch: &str,
    handle: &FetchersHandle,
) -> Result<BTreeMap<DeviceName, Option<Project>>> {
    let (_, _, mirror_fd) = handle
        .source_dir_by_ref_or_commit_id(
            &RepoUrl("https://github.com/LineageOS/mirror".to_string()),
            &GitRefOrCommitId::GitRef(GitRef("refs/heads/main".to_string())),
        )
        .await
        .context("failed to fetch LineageOS/mirror repo")?;

    let mirror_manifest_instructions =
        repo_manifest::recursively_read_manifest(mirror_fd.as_fd(), Path::new("default.xml"))
            .context("failed to read mirror manifest")?;

    let repo_relurls = mirror_manifest_instructions
        .into_iter()
        .filter_map(|i| match i {
            Instruction::Project(Project { relative_url, .. }) => Some(relative_url.0),
            _ => None,
        })
        .collect::<Vec<_>>();

    let (_, _, hudson_fd) = handle
        .source_dir_by_ref_or_commit_id(
            &RepoUrl("https://github.com/LineageOS/hudson".to_string()),
            &GitRefOrCommitId::GitRef(GitRef("refs/heads/main".to_string())),
        )
        .await
        .context("failed to fetch LineageOS/hudson repo")?;

    let lbt_file = openat(
        hudson_fd.as_fd(),
        Path::new("lineage-build-targets"),
        OFlag::O_RDONLY | OFlag::O_CLOEXEC,
        Mode::empty(),
    )
    .context("failed to open lineage-build-targets file")?;

    let lbt_file = BufReader::new(File::from(lbt_file));
    let mut device_repo_candidates = BTreeMap::<DeviceName, Vec<Project>>::new();
    for line in lbt_file.lines() {
        let line = line.context("failed to read line from lineage-build-targets file")?;
        if line.starts_with('#') || line == "" {
            continue;
        }
        match &line.split(' ').collect::<Vec<_>>()[..] {
            [codename, _variant, _branch, _period] => {
                let candidates: Vec<_> = repo_relurls
                    .iter()
                    .filter_map(|relurl| {
                        match relurl
                            .strip_prefix("LineageOS/android_device_")
                            .and_then(|x| x.strip_suffix(&format!("_{codename}")))
                        {
                            Some(vendor) => {
                                let device_project = Project {
                                    relative_url: RelativeUrl(relurl.clone()),
                                    source_tree_path: Some(
                                        PathBuf::from("device").join(vendor).join(codename),
                                    ),
                                    remote: Some(RemoteName("github".to_string())),
                                    revision: Some(GitRepoRevision(branch.to_string())),
                                    groups: Groups(BTreeSet::new()),
                                    linkfiles: vec![],
                                    copyfiles: vec![],
                                };
                                Some(device_project)
                            }
                            None => None,
                        }
                    })
                    .collect();

                if candidates.len() == 0 {
                    return Err(anyhow!(
                        "no matching device repos found for {codename} in the GitHub LineageOS org"
                    ));
                }

                device_repo_candidates.insert(DeviceName(codename.to_string()), candidates);
            }
            _ => {
                return Err(anyhow!(
                    "invalid line in LineageOS/hudson lineage-build-targets file"
                ));
            }
        }
    }

    let mut jhs = JoinSet::new();
    for (device_name, candidate_projects) in device_repo_candidates {
        let branch = branch.to_string();
        let handle = handle.clone();
        jhs.spawn(async move {
            // we check which ones of the matching repositories have the branch we're looking for.
            // source for this weird hacky behaviour:
            // https://github.com/LineageOS/android_vendor_lineage/blob/d747e9abec858434d4967eb5fa9cd3e87c5cc7b0/build/tools/roomservice.py#L379
            let mut matching_projects: Vec<Project> = vec![];
            for project in candidate_projects {
                // TODO(cyclic-pentane): we jankily assume that the remote (we hard-coded above) is
                // `github` and faux-resolve it to check the device refs. this should be done better.
                let candidate_url =
                    RepoUrl(format!("https://github.com/{}", project.relative_url.0));
                let commit_id = handle
                    .resolve_ref_or_commit_id(
                        &candidate_url,
                        &GitRefOrCommitId::GitRef(GitRef(format!("refs/heads/{}", &branch))),
                    )
                    .await
                    .context("failed to look up branch in device repo")?;

                match commit_id {
                    Some(_) => matching_projects.push(project),
                    None => (),
                }
            }

            let project = match &matching_projects[..] {
                [project] => Some(project.clone()),
                [] => None,
                // roomservice.py just takes the alphabetically(?) first matching device repo in this
                // case. we chicken out instead
                _ => {
                    return Err(anyhow!(
                        "more than one matching device repo found in LineageOS GitHub org"
                    ));
                }
            };
            Ok((device_name, project))
        });
    }

    let mut device_repos = BTreeMap::new();
    while let Some(r) = jhs.join_next().await {
        let (device_name, project) = r
            .context("failed to join task")?
            .context("failed to filter candidate device repos")?;
        device_repos.insert(device_name, project);
    }

    Ok(device_repos)
}

#[derive(Debug, Serialize)]
enum LineageDepsError {
    DeviceRepoMissing,
    BranchMissingInDependency,
    MissingMuppetsRepo,
}

async fn recursively_read_lineage_deps(
    project: &Project,
    manifest: &mut ManifestState,
    manifest_dir: BorrowedFd<'_>,
    handle: &FetchersHandle,
) -> Result<Result<(), LineageDepsError>> {
    let project = project
        .add_to(manifest, true)
        .context("failed to add project to manifest")?;
    let (repo_url, commit_id, nix_hash) =
        match prefetch_project(&project, &manifest.config, handle).await {
            Ok(x) => x,
            Err(PrefetchProjectError::RefNotFound) => {
                return Ok(Err(LineageDepsError::BranchMissingInDependency));
            }
            Err(e) => return Err(e).context("failed to prefetch project")?,
        };
    let fd = handle
        .source_dir_fd(&(repo_url, commit_id, nix_hash))
        .await
        .context("failed to open source dir")?;

    let file = openat(
        fd.clone(),
        Path::new("lineage.dependencies"),
        OFlag::O_RDONLY,
        Mode::empty(),
    );

    let deps: Vec<Dependency> = match file {
        Ok(file) => serde_json::from_reader(File::from(file))
            .context("failed to deserialize lineage.dependencies file")?,
        Err(Errno::ENOENT) => vec![],
        Err(e) => return Err(e).context("failed to open lineage.dependencies file"),
    };

    for dep in deps {
        let dep = dep
            .resolve(&manifest.config)
            .context("failed to resolve lineage dependency")?;
        match dep {
            ResolvedDependency::Project(project) => match Box::pin(recursively_read_lineage_deps(
                &project,
                manifest,
                manifest_dir,
                handle,
            ))
            .await
            .with_context(|| {
                format!(
                    "failed to recurse into dependencies of repo {}",
                    project.relative_url.0
                )
            })? {
                Ok(r) => r,
                Err(e) => return Ok(Err(e)),
            },
            ResolvedDependency::Include(Include { path }) => {
                let instructions = repo_manifest::recursively_read_manifest(manifest_dir, &path)
                    .context("failed to recursively read included submanifest")?;
                for instruction in instructions {
                    if let Instruction::Project(project) = instruction {
                        project.add_to(manifest, true).context(
                            "failed to add project from included submanifest to manifest state"
                        )?;
                    } else {
                        return Err(anyhow!("included submanifest contains an unexpected instruction (other than <project />): {:?}", instruction));
                    }
                }
            }
        }
    }

    Ok(Ok(()))
}

#[derive(Debug, Clone, Parser)]
pub struct LineageOS {
    #[arg(short = 'b', long = "branch")]
    pub branch: String,

    #[arg(short = 'o', long = "output")]
    pub lockfile_path: PathBuf,
}

impl CommandLike for LineageOS {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        let manifest_url = RepoUrl("https://github.com/LineageOS/android".to_string());
        let git_ref = GitRefOrCommitId::GitRef(GitRef(format!("refs/heads/{}", self.branch)));
        Box::pin(async move {
            let (_, _, fd) = handle
                .source_dir_by_ref_or_commit_id(&manifest_url, &git_ref)
                .await
                .context("failed to fetch LineageOS manifest")?;

            let instructions =
                repo_manifest::recursively_read_manifest(fd.as_fd(), Path::new("default.xml"))
                    .context("failed to recursively read manifest files")?;

            let mut manifest = ManifestState::new(manifest_url);
            for instruction in instructions {
                instruction
                    .execute_on(&mut manifest)
                    .context("failed to apply instruction to manifest state")?;
            }

            let projects = prefetch_projects(&manifest, &handle)
                .await
                .context("failed to prefetch projects in git-repo manifest")?;

            let (_, _, muppets_fd) = handle
                .source_dir_by_ref_or_commit_id(
                    &RepoUrl("https://github.com/TheMuppets/manifests".to_string()),
                    &git_ref,
                )
                .await
                .context("failed to fetch TheMuppets manifest")?;

            let muppets_instructions = repo_manifest::recursively_read_manifest(
                muppets_fd.as_fd(),
                Path::new("muppets.xml"),
            )
            .context("failed to recursively read muppets manifest files")?;

            let devices = get_all_devices(&self.branch, &handle)
                .await
                .context("failed to fetch device list")?;

            let mut devices_jhs = JoinSet::new();
            for (device_name, device_project) in devices {
                let Some(device_project) = device_project else {
                    devices_jhs.spawn(async move {
                        Ok((device_name, Err(LineageDepsError::DeviceRepoMissing)))
                    });
                    continue;
                };
                let mut device_manifest = manifest.clone();
                let fd = fd.clone();
                let handle = handle.clone();
                let muppets_instructions = muppets_instructions.clone();
                let projects = projects.clone();
                devices_jhs.spawn(async move {
                    match recursively_read_lineage_deps(&device_project, &mut device_manifest, fd.as_fd(), &handle)
                        .await
                        .with_context(|| format!("failed to recursively fetch lineage dependencies of device repo for device {}", device_name.0))? {
                            Ok(()) => (),
                            Err(e) => return Ok((device_name, Err(e))),
                    }

                    let device_muppets_instructions = muppets_instructions
                        .iter()
                        .filter(|x| match x {
                            Instruction::Project(Project { groups, .. }) => groups.0.contains(&format!("muppets_{}", device_name.0)),
                            _ => false,
                        })
                        .cloned()
                        .collect::<Vec<_>>();

                    for instruction in device_muppets_instructions {
                        instruction.execute_on(&mut device_manifest)
                            .context("failed to execute instruction on device-specific manifest state")?;
                    }

                    // TODO(cyclic-pentane): this is horrible jank since we check whether any of the
                    // projects has a git ref that doesn't exist in its repo, and then assume that
                    // it's a missing muppets repo since all the other repos got prefetched
                    // resolved earlier already.
                    let mut device_projects = match prefetch_projects(&device_manifest, &handle).await {
                        Ok(device_projects) => device_projects,
                        Err(PrefetchProjectError::RefNotFound) => return Ok((device_name, Err(LineageDepsError::MissingMuppetsRepo))),
                        Err(e) => return Err(e).context("failed to prefetch projects")?,
                    };

                    for relpath in projects.keys() {
                        match device_projects.remove(relpath) {
                            Some(_) => (),
                            None => return Err(anyhow!("project {} is no longer present in the device-specific manifest for {}", relpath.display(), device_name.0)),
                        }
                    }

                    Ok((device_name, Ok(device_projects)))
                });
            }

            let mut device_repos = BTreeMap::new();
            while let Some(r) = devices_jhs.join_next().await {
                let (device_name, device_projects) = r
                    .context("failed to join device deps fetcher task")?
                    .context("failed to fetch device deps")?;
                device_repos.insert(device_name, device_projects);
            }

            #[derive(Serialize)]
            struct LineageLockfile {
                common: BTreeMap<PathBuf, lockfile::Project>,
                device_specific: BTreeMap<
                    DeviceName,
                    Result<BTreeMap<PathBuf, lockfile::Project>, LineageDepsError>,
                >,
            }

            let lockfile = LineageLockfile {
                common: projects,
                device_specific: device_repos,
            };

            let file = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&self.lockfile_path)
                .context("failed to open output lockfile for writing")?;

            serde_json::to_writer_pretty(file, &lockfile)
                .context("failed to serialize lockfile")?;

            Ok(())
        })
    }
}
