use crate::Fetcher;
use anyhow::{Context, Result, anyhow};
use reqwest::{Client, Url};

#[derive(Default)]
pub(crate) struct HttpGet(Client);

impl Fetcher for HttpGet {
    type Args = Url;
    type CacheKey = Url;
    type Output = String;

    async fn execute(&mut self, url: &Self::Args) -> Result<String> {
        self.0
            .get(url.clone())
            .send()
            .await
            .context("failed to send request")?
            .text()
            .await
            .context("failed to read response body")
    }

    fn cache_key(url: &Url) -> Url {
        url.clone()
    }
}
