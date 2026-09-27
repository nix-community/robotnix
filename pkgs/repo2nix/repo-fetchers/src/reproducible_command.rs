use anyhow::{anyhow, Context, Result};
use crate::Fetcher;
use log::info;
use sha2::{Digest, Sha256};
use std::process::Stdio;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;


#[derive(Default)]
pub struct ReproducibleCommand;

impl Fetcher for ReproducibleCommand {
    type Args = (Vec<String>, String);
    type Output = String;
    type CacheKey = [u8; 32];

    async fn execute(&mut self, (args, stdin): &(Vec<String>, String)) -> Result<String> {
        info!("executing command {args:?}");
        let mut child = Command::new(args.get(0).context("command vec is empty")?)
            .args(&args[1..])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("failed to spawn command")?;

        child
            .stdin
            .as_mut()
            .unwrap()
            .write_all(&stdin.as_bytes())
            .await
            .context("failed to write stdin to child process")?;

        let out = child
            .wait_with_output()
            .await
            .context("failed to run child process to completion")?;

        if !out.status.success() {
            return Err(anyhow!("command failed with stderr: {:?}", String::from_utf8_lossy(&out.stderr)));
        }

        Ok(
            <str>::from_utf8(&out.stdout[..]).context("output contains invalid utf8")?.to_string()
        )
    }

    fn cache_key((args, stdin): &(Vec<String>, String)) -> [u8; 32] {
        let mut hasher = Sha256::new();
        for arg in args {
            hasher.update(arg.len().to_le_bytes());
            hasher.update(arg);
        }
        hasher.update(stdin.len().to_le_bytes());
        hasher.update(stdin);
        hasher.finalize().into()
    }
}
