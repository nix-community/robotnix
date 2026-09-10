use anyhow::{Context, Result, anyhow};
use crate::Fetcher;
use log::*;
use reqwest::{Client, Url, StatusCode};
use reqwest::header::HeaderMap;
use std::time::Duration;

#[derive(Default)]
pub struct HttpGet(Client);

impl Fetcher for HttpGet {
    type Args = (Url, HeaderMap);
    type CacheKey = Url;
    type Output = String;

    async fn execute(&mut self, (url, headers): &Self::Args) -> Result<String> {
        info!("GET {url}");
        let mut backoff = Duration::from_secs(1);
        loop {
            let resp = self.0
                .get(url.clone())
                .header("User-Agent", "robotnix repo2nix (reqwest)")
                .headers(headers.clone())
                .send()
                .await
                .context("failed to send request")?;

            match resp.status() {
                StatusCode::OK => return resp
                    .text()
                    .await
                    .context("failed to read response body"),
                StatusCode::TOO_MANY_REQUESTS => {
                    warn!("got 429 Too Many Requests for {url}, backing off for {} seconds", backoff.as_secs());
                    tokio::time::sleep(backoff)
                        .await;
                    backoff *= 2;
                    continue;
                },
                _ => return Err(anyhow!("request to {url} failed with status code {} and body {}", resp.status(), resp.text().await.context("failed to get body of error response")?)),
            }
        }
    }

    fn cache_key((url, _): &Self::Args) -> Url {
        url.clone()
    }
}
