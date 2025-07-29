use std::path::{Path, PathBuf};
use std::collections::BTreeMap;
use tokio::fs;
use serde::{Serialize, Deserialize};
use serde_yml::{self, Value};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ReadAdevtoolConfigError {
    #[error("couldn't read adevtool device config file `{0}`")]
    IO(PathBuf, #[source] std::io::Error),
    #[error("adevtool config file contains invalid YAML")]
    Parse(#[from] serde_yml::Error),
    #[error("adevtool config file has an invalid YAML structure")]
    WrongYAMLFormat,
    #[error("multiple build IDs specified in the includes of adevtool config file")]
    MultipleBuildIDsInIncludes,
    #[error("no build ID in config files for device `{0}`")]
    NoBuildIDForDevice(String),
    #[error("build `{0} {1}` not found in adevtool build-index-main.yml")]
    NotFoundInBuildIndex(String, String),
}

pub async fn recursively_get_build_id(path: &Path) -> Result<Option<String>, ReadAdevtoolConfigError> {
    let text = fs::read(path).await.map_err(|e| ReadAdevtoolConfigError::IO(path.to_path_buf(), e))?;
    let value: Value = serde_yml::from_slice(&text)?;

    match value {
        Value::Mapping(mapping) => {
            if let Some(Value::Mapping(device)) = mapping.get("device") {
                if let Some(Value::String(build_id)) = device.get("build_id") {
                    return Ok(Some(build_id.clone()));
                }
            }

            match mapping.get("includes") {
                Some(Value::Sequence(seq)) => {
                    let mut build_id = None;
                    for entry in seq.iter() {
                        match entry {
                            Value::String(include_path) => {
                                match Box::pin(recursively_get_build_id(
                                        &path
                                        .parent()
                                        .unwrap()
                                        .join(include_path)
                                )).await? {
                                    Some(new_build_id) => match build_id {
                                        None => {
                                            build_id = Some(new_build_id);
                                        },
                                        Some(_) => return Err(ReadAdevtoolConfigError::MultipleBuildIDsInIncludes),
                                    },
                                    None => (),
                                };
                            },
                            _ => return Err(ReadAdevtoolConfigError::WrongYAMLFormat),
                        };
                    }

                    Ok(build_id)
                },
                Some(_) => Err(ReadAdevtoolConfigError::WrongYAMLFormat),
                None => Ok(None),
            }
        },
        _ => Err(ReadAdevtoolConfigError::WrongYAMLFormat),
    }
}

pub async fn get_build_id(adevtool_path: &Path, device: &str) -> Result<Option<String>, ReadAdevtoolConfigError> {
    let config_path = adevtool_path
        .join("config/device")
        .join(&format!("{device}.yml"));

    recursively_get_build_id(&config_path).await
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildIndexProperties {
    pub desc: Option<String>,
    pub factory: Option<String>,
    pub ota: Option<String>,
    #[serde(rename = "vendor/google_devices")]
    pub vendor_google_devices: Option<String>,
}

type BuildIndex = BTreeMap<String, BuildIndexProperties>;

pub async fn get_build_index(adevtool_path: &Path) -> Result<BuildIndex, ReadAdevtoolConfigError> {
    let build_index_path = adevtool_path
        .join("config/build-index/build-index-main.yml");

    let text = fs::read(&build_index_path)
        .await
        .map_err(|e| ReadAdevtoolConfigError::IO(build_index_path.clone(), e))?;

    Ok(serde_yml::from_slice(&text)?)
}

#[derive(Debug, Serialize)]
pub struct VendorImgMetadata {
    vendor_build_id: String,
    build_index_props: BuildIndexProperties,
}

pub async fn get_vendor_img_metadata(adevtool_path: &Path, devices: &[String]) -> Result<BTreeMap<String, VendorImgMetadata>, ReadAdevtoolConfigError> {
    let build_index = get_build_index(&adevtool_path).await?;

    let mut metadata = BTreeMap::new();
    for device in devices.iter() {
        let build_id = get_build_id(&adevtool_path, device)
            .await?
            .ok_or(ReadAdevtoolConfigError::NoBuildIDForDevice(device.clone()))?;
        metadata.insert(device.clone(), VendorImgMetadata {
            build_index_props: build_index
                .get(&format!("{device} {build_id}"))
                .ok_or(ReadAdevtoolConfigError::NotFoundInBuildIndex(
                        device.clone(),
                        build_id.clone()
                ))?.clone(),
            vendor_build_id: build_id,
        });
    }

    Ok(metadata)
}
