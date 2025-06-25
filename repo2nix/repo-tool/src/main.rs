use std::path::PathBuf;
use clap::Parser;
use url::Url;
use tokio;
use repo_manifest::resolver::{
    Project,
    GitRepoRef,
};
use crate::fetch::nix_prefetch_git;
use crate::lock::update_lock;

mod fetch;
mod lock;

#[derive(Parser)]
enum Args {
    Fetch {
        manifest_url: String,
        lockfile: PathBuf,
    },
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    match args {
        Fetch => {
            let manifest_fetch = nix_prefetch_git("https://github.com/LineageOS/android", "refs/heads/lineage-22.2", false, false).await;
            println!("{:?}", manifest_fetch);

            let lock = update_lock(
                &Project {
                    name: "android".to_string(),
                    path: PathBuf::from("android"),
                    groups: vec![],
                    linkfiles: vec![],
                    copyfiles: vec![],
                    repo_ref: GitRepoRef {
                        repo_url: Url::parse("https://github.com/LineageOS/android").unwrap(),
                        revision: "refs/heads/lineage-22.2".to_string(),
                    },
                },
                &None
            ).await;
            println!("{:?}", lock);
        },
    }
}
