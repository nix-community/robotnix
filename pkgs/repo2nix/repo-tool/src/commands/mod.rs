use anyhow::Result;
use clap::Parser;
use enum_dispatch::enum_dispatch;
use repo_fetchers::FetchersHandle;
use std::pin::Pin;

mod grapheneos;
mod lineageos;
mod plain;

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
    #[command(name = "grapheneos")]
    GrapheneOS(grapheneos::GrapheneOS),
}
