use anyhow::{Context, Result, anyhow};
use crate::Fetcher;
use log::info;
use reqwest::{Client, Url};
use reqwest::header::HeaderMap;

#[derive(Default)]
pub(crate) struct HttpGet(Client);

impl Fetcher for HttpGet {
    type Args = (Url, HeaderMap);
    type CacheKey = Url;
    type Output = String;

    async fn execute(&mut self, (url, headers): &Self::Args) -> Result<String> {
        info!("GET {url}");
        self.0
            .get(url.clone())
            .header("User-Agent", "robotnix repo2nix (reqwest)")
            .headers(headers.clone())
            .send()
            .await
            .context("failed to send request")?
            .text()
            .await
            .context("failed to read response body")
    }

    fn cache_key((url, _): &Self::Args) -> Url {
        url.clone()
    }
}
