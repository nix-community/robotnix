use repo_manifest::resolver::{
    Category,
};
use crate::lock::{
    LockfileEntry,
    Lockfile
};
use crate::fetch::{
    git_ls_remote,
    GitLsRemoteError,
};

pub fn tag_device_by_group(lockfile: &mut Lockfile, group_prefix: &str) {
    for (_path, entry) in lockfile.entries.iter_mut() {
        let project = &mut entry.project;
        let device_cats: Vec<_> = project
            .groups
            .iter()
            .filter(|x| x.starts_with(group_prefix))
            .map(|x| x.strip_prefix(group_prefix).unwrap().to_string())
            .map(|x| Category::DeviceSpecific(x))
            .collect();

        if device_cats.len() > 0 && project.categories.iter().all(|x| *x == Category::Default) {
            project.categories = device_cats;
        }
    }
}

pub async fn cleanup_broken_projects(lockfile: &mut Lockfile, group: Option<&str>) -> Result<Vec<LockfileEntry>, GitLsRemoteError> {
    let paths: Vec<_> = lockfile.entries.keys().cloned().collect();
    let mut paths_to_remove = vec![];
    for path in paths {
        let project = &lockfile.entries.get(&path).unwrap().project;
        if group.map(|x| project.groups.contains(&x.to_string())).unwrap_or(true) {
            eprintln!(
                "Checking that `{}` has rev `{}`...",
                project.repo_ref.repo_url,
                project.repo_ref.revision
            );
            match git_ls_remote(
                &project.repo_ref.repo_url.as_str(),
                &project.repo_ref.revision
            ).await {
                Ok(_) => (),
                Err(GitLsRemoteError::RevNotFound) => {
                    eprintln!("Not found.");
                    paths_to_remove.push(path);
                },
                Err(e) => return Err(e),
            }
        }
    }

    let mut removed_entries = vec![];
    for path in paths_to_remove {
        removed_entries.push(lockfile.entries.remove(&path).unwrap());
    }
    Ok(removed_entries)
}
