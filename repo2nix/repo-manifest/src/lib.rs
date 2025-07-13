pub mod xml;
pub mod resolver;

#[cfg(test)]
mod tests {
    use crate::xml::{Manifest, read_manifest_file};
    use crate::resolver::{recursively_read_manifest_files, resolve_manifest};
    use quick_xml;
    use std::path::{Path, PathBuf};
    use url::Url;
    use tokio;

    #[tokio::test]
    async fn basic_parsing() {
        let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("test/android");
        let manifest_xml = recursively_read_manifest_files(&manifest_path, &Path::new("default.xml")).await.unwrap();
    }

    #[tokio::test]
    async fn basic_resolving() {
        let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("test/android");
        let manifest_xml = recursively_read_manifest_files(&manifest_path, &Path::new("default.xml")).await.unwrap();
        let manifest = resolve_manifest(
            &manifest_xml,
            &Url::parse("https://github.com/LineageOS/android/").unwrap()
        ).unwrap();

        for remote in manifest.remotes.values() {
            println!("{:?}", remote);
        }

        println!("{:?}", manifest.default_remote);

        for project in manifest.projects.values() {
            println!("{}", project.repo_ref.repo_url);
        }
    }
}
