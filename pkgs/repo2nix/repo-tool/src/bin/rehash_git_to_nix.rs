use anyhow::{anyhow, Context, Result};
use clap::Parser;
use git2::{Repository, ObjectType, Tree};
use nix_compat::nar::writer::sync::Directory;
use sha2::{Sha256, Digest};
use std::io::Write;
use std::path::PathBuf;

struct Sha256HashWriter(Sha256);

impl Write for Sha256HashWriter {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.update(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[derive(Parser)]
struct CliArgs {
    repo_path: PathBuf,
    commit_id: git2::Oid,
}

fn write_tree_to_nar(repo: &Repository, tree: &Tree, dir: &mut Directory<impl Write>) -> Result<()> {
    let mut tree_entries: Vec<_> = tree.iter().collect();
    tree_entries.sort_by(|entry_a, entry_b| entry_a.name_bytes().cmp(entry_b.name_bytes()));
    for tree_entry in tree_entries {
        let object = tree_entry
            .to_object(repo)
            .context("failed to convert TreeEntry to Object")?;
        let node = dir
            .entry(tree_entry.name_bytes())
            .context("failed to initialise directory node")?;
        match object.kind() {
            Some(ObjectType::Blob) => {
                match tree_entry.filemode() {
                    0o100644 | 0o100755 => { // normal file
                        todo!()
                    },
                    0o120000 => { // symlink
                        todo!()
                    },
                    _ => return Err(anyhow!("unexpected file mode: {:o}", tree_entry.filemode())),
                }
            },
            Some(ObjectType::Tree) => {
                let subtree = object
                    .as_tree()
                    .unwrap();
                let mut subdir = node
                    .directory()
                    .context("failed to initialize new directory")?;
                write_tree_to_nar(&repo, &subtree, &mut subdir)
                    .with_context(|| format!(
                            "failed to write subdir `{}` to NAR",
                            String::from_utf8_lossy(tree_entry.name_bytes())
                    ))?;
            },
            _ => return Err(anyhow!("unexpected object type")),
        }
    }

    Ok(())
}

fn main() -> Result<()> {
    let args = CliArgs::parse();

    let repo = Repository::init(&args.repo_path)
        .context("failed to open repository")?;

    let object = repo
        .find_object(args.commit_id, Some(ObjectType::Commit))
        .context("couldn't find commit in repository")?;
    let commit = object.as_commit().unwrap();
    let tree = commit
        .tree()
        .context("failed to get tree of commit")?;

    let mut hash_writer = Sha256HashWriter(Sha256::new());
    {
        let nar = nix_compat::nar::writer::open(&mut hash_writer)
            .context("failed to initialise NAR writer")?;
        let mut root_dir = nar.directory()
            .context("failed to initialise root dir")?;

        write_tree_to_nar(&repo, &tree, &mut root_dir)
            .context("failed to write root dir")?;
    }

    println!("{:?}", hash_writer.0.finalize());

    todo!()
}
