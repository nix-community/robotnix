use repo_manifest::resolver::{
    Category,
};
use crate::lock::Lockfile;

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
