#!/usr/bin/env python

import json
import os

from robotnix_common import checkout_git, save


def main() -> None:
    data = json.load(open('repo-lineage-17.1.json'))
    anbox_patches = data['anbox-patches']
    git_info = checkout_git(anbox_patches['url'], anbox_patches['rev'])
    topdir = git_info['path']

    output = {}
    for dirpath, dirs, files in os.walk(topdir):
        if any(f.endswith('.patch') for f in files):
            if dirpath.startswith(topdir):
                dirpath = dirpath[len(topdir)+1:]
            output[dirpath] = sorted(files)

    save('patch-metadata.json', output)


if __name__ == '__main__':
    main()
