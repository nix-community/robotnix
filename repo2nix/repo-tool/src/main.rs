use std::path::{Path, PathBuf};
use std::io::ErrorKind;
use clap::Parser;
use url::Url;
use tokio;
use repo_manifest::resolver::{
    recursively_read_manifest_files,
    resolve_manifest,
    GitRepoRef,
};
use crate::fetch::nix_prefetch_git;
use crate::lock::{
    Lockfile,
    ReadWriteLockfileError,
};

mod fetch;
mod lock;

#[derive(Parser)]
enum Args {
    Fetch {
        manifest_url: String,
        lockfile_path: PathBuf,

        #[arg(long, short)]
        branch: String
    },
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    match args {
        Args::Fetch { manifest_url, lockfile_path, branch } => {
            let url = Url::parse(&manifest_url).unwrap();
            let manifest_fetch = nix_prefetch_git(&GitRepoRef {
                repo_url: url.clone(),
                revision: format!("refs/heads/{branch}"),
                fetch_lfs: false,
                fetch_submodules: false,
            }).await.unwrap();

            let manifest_xml = recursively_read_manifest_files(&manifest_fetch.path, Path::new("default.xml")).await.unwrap();
            let manifest = resolve_manifest(&manifest_xml, &url).unwrap();

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
    }
}
