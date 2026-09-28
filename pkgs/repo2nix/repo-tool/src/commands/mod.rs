use anyhow::Result;
use clap::Parser;
use enum_dispatch::enum_dispatch;
use repo_fetchers::FetchersHandle;
use std::pin::Pin;

mod plain;
mod lineageos;
mod lineageos_branches;
mod grapheneos;
mod grapheneos_branches;

#[enum_dispatch]
pub trait CommandLike {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>>;
}

#[derive(Debug, Clone, Parser)]
#[enum_dispatch(CommandLike)]
pub enum Command {
    #[command(name = "plain")]
    Plain(plain::Plain),

    #[command(name = "lineageos")]
    LineageOS(lineageos::LineageOS),

    #[command(name = "lineageos_branches")]
    LineageOSBranches(lineageos_branches::LineageOSBranches),

    #[command(name = "grapheneos")]
    GrapheneOS(grapheneos::GrapheneOS),

    #[command(name = "grapheneos_branches")]
    GrapheneOSBranches(grapheneos_branches::GrapheneOSBranches),
}
