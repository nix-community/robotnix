pub mod xml;
pub mod execute;

use anyhow::{Context, Result};
use crate::xml::{Include, Instruction, Item, Manifest};
use hard_xml::XmlRead;
use nix::fcntl::{openat, OFlag};
use nix::sys::stat::Mode;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::os::fd::BorrowedFd;

pub fn recursively_read_manifest(dir_fd: BorrowedFd, relpath: &Path) -> Result<Vec<Instruction>> {
    let file_fd = openat(
        dir_fd,
        relpath,
        OFlag::O_RDONLY | OFlag::O_CLOEXEC,
        Mode::empty(),
    )
        .context("failed to open manifest file")?;
    let mut file = File::from(file_fd);
    let mut text = String::new();
    file.read_to_string(&mut text)
        .context("failed to read XML from file")?;
    let manifest = Manifest::from_str(&text)
        .context("failed to parse manifest XML")?;

    let mut instructions = vec![];
    for item in manifest.items {
        match item {
            Item::Instruction(instruction) => instructions.push(instruction),
            Item::Include(Include { path }) => {
                let mut new_instructions = recursively_read_manifest(dir_fd, &path)
                    .context("failed to read manifest include")?;
                instructions.append(&mut new_instructions);
            },
        }
    }

    Ok(instructions)
}

#[cfg(test)]
mod tests {
    use crate::execute::{ExecuteOnState, ManifestState};
    use nix::fcntl::open;
    use repo_types::RepoUrl;
    use std::os::fd::AsFd;
    use super::*;

    #[test]
    fn grapheneos_manifest() {
        let dir_fd = open(
            &Path::new(
                env!("CARGO_MANIFEST_DIR")
            )
                .join("test/GrapheneOS_platform_manifest"),
            OFlag::O_RDONLY | OFlag::O_CLOEXEC,
            Mode::empty(),
        )
            .unwrap();

        let instructions = recursively_read_manifest(
            dir_fd.as_fd(),
            &Path::new("default.xml")
        )
            .unwrap();

        let manifest_state = ManifestState::new(
            RepoUrl("https://github.com/GrapheneOS/platform_manifest".to_string()),
        );
        let manifest_state = instructions
            .iter()
            .fold(manifest_state, |mut state, instruction| {
                instruction.execute_on(&mut state).unwrap();
                state
            });

        println!("{:#?}", manifest_state);
    }
}
