use super::CommandLike;
use anyhow::Result;
use clap::Parser;
use repo_fetchers::FetchersHandle;
use std::pin::Pin;

#[derive(Debug, Clone, Parser)]
pub struct GrapheneOS {}

impl CommandLike for GrapheneOS {
    fn run(self, handle: FetchersHandle) -> Pin<Box<dyn Future<Output = Result<()>>>> {
        Box::pin(async move { todo!() })
    }
}
