use anyhow::{Context, Result};
use clap::Parser;
use crate::commands::Command;
use log::*;
use nix_compat::nixhash::NixHash;
use repo_fetchers::FetchersHandle;
use repo_manifest::execute::{ManifestConfigState, ManifestState, ProjectState};
use repo_types::{ForgeSpecificRepoUrl, RepoUrl};
use repo_types::lockfile::{Project, Source};
use std::collections::BTreeMap;
use std::path::PathBuf;
use tokio::task::JoinSet;

pub mod commands;

#[derive(Parser)]
pub struct CliArgs {
    #[arg(short = 'v', long, default_value_t = 2)]
    pub verbosity: usize,

    #[arg(short = 'j', long, default_value_t = 4)]
    pub fetcher_tasks: u64,

    #[arg(long)]
    pub nixhash_lockfile: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Command,
}

pub async fn prefetch_project(project: &ProjectState, config: &ManifestConfigState, handle: &FetchersHandle) -> Result<(RepoUrl, git2::Oid, NixHash)> {
    let repo_url = project
        .base_url
        .join_parts(
            &config.manifest_url,
            &project.relative_url,
        );

    let (commit_id, nix_hash) = handle
        .prefetch_by_ref_or_commit_id(&repo_url, &project.revision)
        .await?;

    Ok((repo_url, commit_id, nix_hash))
}

pub async fn prefetch_projects(state: &ManifestState, handle: &FetchersHandle) -> Result<BTreeMap<PathBuf, Project>> {
    let mut join_set: JoinSet<Result<(PathBuf, Project), anyhow::Error>> = JoinSet::new();
    for (relpath, project) in &state.projects {
        let config = state.config.clone();
        let relpath = relpath.clone();
        let project = project.clone();
        let handle = handle.clone();
        join_set.spawn(async move {
            let (repo_url, commit_id, nix_hash) = prefetch_project(&project, &config, &handle)
                .await?;
            let repo_url = ForgeSpecificRepoUrl::from_repo_url(&repo_url);

            Ok((
                relpath.clone(),
                Project {
                    src: Source {
                        derivation_name: repo_url.derivation_name(&commit_id),
                        commit_id,
                        fetch_url: repo_url.to_fetch_url(&commit_id),
                        mirror_path: repo_url.mirror_path(),
                        hash: nix_hash,
                    },
                    linkfiles: project.linkfiles.clone(),
                    copyfiles: project.copyfiles.clone(),
                    groups: project.groups.clone(),
                }
            ))
        });
    }
    let mut projects = BTreeMap::new();
    while let Some(ret) = join_set.join_next().await {
        let (relpath, project) = ret
            .context("failed to join project fetcher handle")?
            .context("failed to fetch project")?;
        projects.insert(
            relpath,
            project
        );
    }
    Ok(projects)
}
