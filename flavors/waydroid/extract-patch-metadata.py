#!/usr/bin/env python

import json
import os

from robotnix_common import checkout_git, save


def main() -> None:
    data = json.load(open("repo-lineage-17.1.json"))
    waydroid_vendor = data["vendor/extra"]
    git_info = checkout_git(waydroid_vendor["url"], waydroid_vendor["rev"])
    topdir = git_info["path"]

    output = {}
    patches_dir = os.path.join(topdir, "waydroid-patches", "base-patches")
    for dirpath, dirs, files in os.walk(patches_dir):
        if any(f.endswith(".patch") for f in files):
            src_path = dirpath[len(topdir) + 1 :]
            dest_path = dirpath[len(patches_dir) + 1 :]
            output[dest_path] = {
                "dir": src_path,
                "files": sorted(files),
            }

    save("patch-metadata.json", output)


if __name__ == "__main__":
    main()
