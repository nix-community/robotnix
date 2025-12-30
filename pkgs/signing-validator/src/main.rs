use anyhow::{Context, Result, anyhow};
use clap::Parser;
use std::fs::File;
use std::io::{BufReader, Read, Seek};
use std::path::{Path, PathBuf};
use zip::ZipArchive;

const APK_PUBLIC_KEY_SUFFIX: &str = ".x509.pem";
const APK_PRIVATE_KEY_SUFFIX: &str = ".pk8";

#[derive(Debug, Parser)]
struct Args {
    #[arg(long = "extra_apks")]
    extra_apks: Vec<String>,

    #[arg(long = "extra_apex_payload_key")]
    extra_apex_payload_keys: Vec<String>,

    #[arg(long = "key_mapping")]
    key_mappings: Vec<String>,

    #[arg(long)]
    fail_on_unused_flags: bool,

    target_files: PathBuf,
}

#[derive(Debug, Eq, PartialEq, Clone)]
enum Key {
    Presigned,
    External,
    Path(PathBuf),
}

impl<T: AsRef<str>> From<T> for Key {
    fn from(key_str: T) -> Self {
        Key::Path(key_str.as_ref().into())
    }
}

impl Key {
    fn try_from_privkey<T: AsRef<str>>(path: T) -> Result<Self> {
        Ok(match path.as_ref() {
            "PRESIGNED" => Key::Presigned,
            "EXTERNAL" => Key::External,
            s => Key::Path(
                s.strip_suffix(APK_PRIVATE_KEY_SUFFIX)
                    .ok_or(anyhow!(
                        "APK private key {} doesn't end in {}",
                        path.as_ref(),
                        APK_PRIVATE_KEY_SUFFIX
                    ))?
                    .into(),
            ),
        })
    }

    fn try_from_pubkey<T: AsRef<str>>(path: T) -> Result<Self> {
        Ok(match path.as_ref() {
            "PRESIGNED" => Key::Presigned,
            "EXTERNAL" => Key::External,
            s => Key::Path(
                s.strip_suffix(APK_PUBLIC_KEY_SUFFIX)
                    .ok_or(anyhow!(
                        "APK public key {} doesn't end in {}",
                        path.as_ref(),
                        APK_PUBLIC_KEY_SUFFIX
                    ))?
                    .into(),
            ),
        })
    }

    fn from_apex_privkey<T: AsRef<str>>(path: T) -> Self {
        match path.as_ref() {
            "PRESIGNED" => Key::Presigned,
            "EXTERNAL" => Key::External,
            s => Key::Path(s.into()),
        }
    }
}

#[derive(Debug)]
struct Apk {
    name: String,
    key: Key,
}

#[derive(Debug)]
struct Apex {
    name: String,
    container_key: Key,
    payload_key: Key,
}

#[derive(Debug)]
struct ApexPayloadKey {
    name: String,
    payload_key: Key,
}

#[derive(Debug)]
struct KeyMapping {
    from: Key,
    to: Key,
}

fn parse_extra_apks(arg: &str) -> Result<Vec<Apk>> {
    match &arg.split('=').collect::<Vec<_>>()[..] {
        [names, key] => {
            let mut apks = vec![];
            for name in names.split(",") {
                apks.push(Apk {
                    name: name.to_string(),
                    key: Key::from(key),
                });
            }
            Ok(apks)
        }
        _ => Err(anyhow!("Malformed --extra_apks argument: {}", arg)),
    }
}

fn parse_extra_apex_payload_key(arg: &str) -> Result<ApexPayloadKey> {
    match &arg.split('=').collect::<Vec<_>>()[..] {
        [name, payload_key] => Ok(ApexPayloadKey {
            name: name.to_string(),
            payload_key: Key::from(payload_key),
        }),
        _ => Err(anyhow!(
            "Malformed --extra_apex_payload_key argument: {}",
            arg
        )),
    }
}

fn parse_key_mapping(arg: &str) -> Result<KeyMapping> {
    match &arg.split('=').collect::<Vec<_>>()[..] {
        [from, to] => Ok(KeyMapping {
            from: from.into(),
            to: to.into(),
        }),
        _ => Err(anyhow!("Malformed --key_mapping argument: {}", arg)),
    }
}

fn parse_apkcerts<R>(archive: &mut ZipArchive<R>) -> Result<(Vec<Apk>, Option<String>)>
where
    R: Seek,
    R: Read,
{
    let mut apkcerts = archive
        .by_path(Path::new("META/apkcerts.txt"))
        .context("Failed to read META/apkcerts.txt from archive")?;
    let mut apkcerts_str = "".to_string();
    apkcerts
        .read_to_string(&mut apkcerts_str)
        .context("Failed to read contents of apkcerts.txt")?;

    let mut apks = vec![];
    let mut compressed_extension = None;
    for (i, line) in apkcerts_str.split('\n').enumerate().filter(|x| x.1 != "") {
        let mut name = None;
        let mut certificate = None;
        let mut private_key = None;
        let mut compressed = None;
        let mut _partition = None;
        for field in line.split(' ') {
            match &field.split('=').collect::<Vec<_>>()[..] {
                [k, v] => {
                    let v = v
                        .strip_prefix('"')
                        .and_then(|x| x.strip_suffix('"'))
                        .ok_or(anyhow!(
                            "Malformed apkcerts.txt field in line {}: {}",
                            i,
                            line
                        ))?
                        .to_string();
                    match *k {
                        "name" => name = Some(v),
                        "certificate" => certificate = Some(v),
                        "private_key" => private_key = Some(v),
                        "compressed" => compressed = Some(v),
                        "partition" => _partition = Some(v),
                        f => return Err(anyhow!("Unknown field {}", f)),
                    }
                }
                _ => {
                    return Err(anyhow!(
                        "Malformed field {} in apkcerts.txt line {}",
                        field,
                        i
                    ));
                }
            }
        }

        if let Some(compressed) = compressed {
            let compressed = format!(".{compressed}");
            match compressed_extension {
                None => compressed_extension = Some(compressed),
                Some(s) => {
                    return Err(anyhow!(
                        "Conflicting compressed extensions `{}` and `{}` in apkcerts.txt",
                        compressed,
                        s
                    ));
                }
            }
        }

        let name = name.ok_or(anyhow!("Missing field `name` in apkcerts.txt line {}", i))?;
        let certificate_path = certificate.ok_or(anyhow!(
            "Missing field `certificate` in apkcerts.txt line {}",
            i
        ))?;
        let private_key_path = private_key.ok_or(anyhow!(
            "Missing field `private_key` in apkcerts.txt line {}",
            i
        ))?;

        let cert =
            Key::try_from_pubkey(certificate_path).context("Failed to parse APK public key")?;

        if let Key::Path(_) = cert {
            let priv_key = Key::try_from_privkey(private_key_path)
                .context("Failed to parse APK private key")?;
            if cert != priv_key {
                return Err(anyhow!(
                    "cert name ({cert:?}) doesn't match private key name ({priv_key:?}) in apkcerts.txt line {i}"
                ));
            }
        }
        apks.push(Apk {
            name: name,
            key: cert,
        });
    }

    Ok((apks, compressed_extension))
}
fn parse_apexkeys<R>(archive: &mut ZipArchive<R>) -> Result<Vec<Apex>>
where
    R: Seek,
    R: Read,
{
    let mut apexkeys = archive
        .by_path(Path::new("META/apexkeys.txt"))
        .context("Failed to read META/apexkeys.txt from archive")?;
    let mut apexkeys_str = "".to_string();
    apexkeys
        .read_to_string(&mut apexkeys_str)
        .context("Failed to read contents of apexkeys.txt")?;

    let mut apexes = vec![];
    for (i, line) in apexkeys_str.split('\n').enumerate().filter(|x| x.1 != "") {
        let mut name = None;
        // Yes, sign_target_files_apks compares the container
        // keys but not the payload keys.
        let mut _public_key = None;
        let mut private_key = None;
        let mut container_certificate = None;
        let mut container_private_key = None;
        let mut _partition = None;
        let mut _sign_tool = None;
        for field in line.split(' ') {
            match &field.split('=').collect::<Vec<_>>()[..] {
                [k, v] => {
                    let v = v
                        .strip_prefix('"')
                        .and_then(|x| x.strip_suffix('"'))
                        .ok_or(anyhow!(
                            "Malformed apkcerts.txt field in line {}: {}",
                            i,
                            line
                        ))?
                        .to_string();
                    match *k {
                        "name" => name = Some(v),
                        "public_key" => _public_key = Some(v),
                        "private_key" => private_key = Some(v),
                        "container_certificate" => container_certificate = Some(v),
                        "container_private_key" => container_private_key = Some(v),
                        "partition" => _partition = Some(v),
                        "sign_tool" => _sign_tool = Some(v),
                        f => return Err(anyhow!("Unknown field {}", f)),
                    }
                }
                _ => {
                    return Err(anyhow!(
                        "Malformed field {} in apexkeys.txt line {}",
                        field,
                        i
                    ));
                }
            }
        }

        let name = name.ok_or(anyhow!("Missing field `name` in apexkeys.txt line {}", i))?;
        let payload_private_key = private_key.ok_or(anyhow!(
            "Missing field `private_key` in apexkeys.txt line {}",
            i
        ))?;
        let container_certificate = container_certificate.ok_or(anyhow!(
            "Missing field `container_certificate` in apexkeys.txt line {}",
            i
        ))?;
        let container_private_key = container_private_key.ok_or(anyhow!(
            "Missing field `container_private_key` in apexkeys.txt line {}",
            i
        ))?;

        let cert = Key::try_from_pubkey(container_certificate)
            .context("Failed to parse APK public key")?;

        if let Key::Path(_) = cert {
            let priv_key = Key::try_from_privkey(container_private_key)
                .context("Failed to parse APK private key")?;
            if cert != priv_key {
                return Err(anyhow!(
                    "cert name ({cert:?}) doesn't match private key name ({priv_key:?}) in apexkeys.txt line {i}"
                ));
            }
        }
        apexes.push(Apex {
            name: name,
            container_key: cert,
            payload_key: Key::from_apex_privkey(payload_private_key),
        });
    }

    Ok(apexes)
}

fn get_apk_names<R>(
    archive: &mut ZipArchive<R>,
    compressed_extension: &Option<String>,
) -> Result<Vec<String>>
where
    R: Read,
    R: Seek,
{
    let mut apks = vec![];
    for i in 0..archive.len() {
        let file = archive
            .by_index(i)
            .context("Failed reading file from archive")?;
        let path = file
            .enclosed_name()
            .context("Failed reading enclosed filename")?;
        let filename = path.file_name();

        let apk_name = match filename {
            Some(name) => {
                let mut name = name.to_str().ok_or(anyhow!("Error decoding file name"))?;

                if let Some(compressed_extension) = compressed_extension {
                    name = name.strip_suffix(compressed_extension).ok_or(anyhow!(
                        "File name doesn't end in compressed extension {:?}",
                        compressed_extension
                    ))?;
                }

                name.to_string()
            }
            None => continue,
        };
        if apk_name.ends_with(".apk") {
            apks.push(apk_name.to_string());
        }
    }
    Ok(apks)
}

fn main() -> Result<()> {
    let args = Args::parse();

    let extra_apks = args
        .extra_apks
        .iter()
        .map(|x| parse_extra_apks(&x))
        .collect::<Result<Vec<Vec<Apk>>>>()?
        .into_iter()
        .flatten()
        .collect::<Vec<Apk>>();
    let extra_apex_payload_keys = args
        .extra_apex_payload_keys
        .iter()
        .map(|x| parse_extra_apex_payload_key(&x))
        .collect::<Result<Vec<ApexPayloadKey>>>()?;
    let key_mappings: Vec<KeyMapping> = args
        .key_mappings
        .iter()
        .map(|x| parse_key_mapping(&x))
        .collect::<Result<Vec<KeyMapping>>>()?;

    let file = File::open(args.target_files).unwrap();
    let reader = BufReader::new(file);

    let mut archive = zip::ZipArchive::new(reader).unwrap();
    let (apks, extension) = parse_apkcerts(&mut archive)?;
    let apk_names = get_apk_names(&mut archive, &extension)?;
    let apks: Vec<_> = apks
        .into_iter()
        .filter(|apk| apk_names.contains(&apk.name))
        .collect();
    let apexes = parse_apexkeys(&mut archive)?;

    // For each APK and APEX, mark whether their keys have already been replaced
    let mut apks: Vec<_> = apks.into_iter().map(|x| (x, false)).collect();

    let mut apexes: Vec<_> = apexes
        .into_iter()
        .map(|x| (x, false, false)) // container key, payload key
        .collect();

    // For each type of flag, mark whether it has already been used
    let mut extra_apks: Vec<_> = extra_apks.into_iter().map(|x| (x, false)).collect();

    let mut key_mappings: Vec<_> = key_mappings.into_iter().map(|x| (x, false)).collect();

    let mut extra_apex_payload_keys: Vec<_> = extra_apex_payload_keys
        .into_iter()
        .map(|x| (x, false))
        .collect();

    for (apk, changed) in apks.iter_mut() {
        for (extra_apk, used) in extra_apks.iter_mut() {
            if apk.name == extra_apk.name {
                apk.key = extra_apk.key.clone();
                *changed = true;
                *used = true;
                break;
            }
        }

        for (key_mapping, used) in key_mappings.iter_mut() {
            if apk.key == key_mapping.from {
                apk.key = key_mapping.to.clone();
                *changed = true;
                *used = true;
                break;
            }
        }
    }

    for (apex, container_changed, payload_changed) in apexes.iter_mut() {
        for (extra_apk, used) in extra_apks.iter_mut() {
            if apex.name == extra_apk.name {
                apex.container_key = extra_apk.key.clone();
                *container_changed = true;
                *used = true;
                break;
            }
        }

        for (key_mapping, used) in key_mappings.iter_mut() {
            if apex.container_key == key_mapping.from {
                apex.container_key = key_mapping.to.clone();
                *container_changed = true;
                *used = true;
                break;
            }
        }

        for (extra_apex_payload_key, used) in extra_apex_payload_keys.iter_mut() {
            if apex.name == extra_apex_payload_key.name {
                apex.payload_key = extra_apex_payload_key.payload_key.clone();
                *payload_changed = true;
                *used = true;
                break;
            }
        }
    }

    let mut all_keys_replaced = true;
    for (apk, changed) in apks.iter() {
        if let Key::Path(_) = apk.key {
            if !changed {
                eprintln!("Key for APK {} has not been replaced", apk.name);
                all_keys_replaced = false;
            }
        }
    }

    for (apex, container_changed, payload_changed) in apexes.iter() {
        if let Key::Path(_) = apex.container_key {
            if !container_changed {
                eprintln!("Container key for APEX {} has not been replaced", apex.name);
                all_keys_replaced = false;
            }
        }
        if let Key::Path(_) = apex.payload_key {
            if !payload_changed {
                eprintln!("Payload key for APEX {} has not been replaced", apex.name);
                all_keys_replaced = false;
            }
        }
    }

    let mut all_flags_used = true;
    for (extra_apk, used) in extra_apks.iter() {
        if !used {
            eprintln!(
                "extra_apks flag for APK {}, key {:?} is never used",
                extra_apk.name, extra_apk.key
            );
            all_flags_used = false;
        }
    }

    for (key_mapping, used) in key_mappings.iter() {
        if !used {
            eprintln!(
                "key_mapping flag from {:?} to {:?} is never used",
                key_mapping.from, key_mapping.to
            );
            all_flags_used = false;
        }
    }

    for (extra_apex_payload_key, used) in extra_apex_payload_keys.iter() {
        if !used {
            eprintln!(
                "extra_apex_payload_key flag for APEX {}, payload key {:?} is never used",
                extra_apex_payload_key.name, extra_apex_payload_key.payload_key
            );
            all_flags_used = false;
        }
    }

    if all_keys_replaced {
        if all_flags_used || !args.fail_on_unused_flags {
            Ok(())
        } else {
            Err(anyhow!(
                "Not all sign_target_files_apks flags have been used."
            ))
        }
    } else {
        Err(anyhow!(
            "Some keys would not be replaced by the given sign_target_files_apks flags."
        ))
    }
}
