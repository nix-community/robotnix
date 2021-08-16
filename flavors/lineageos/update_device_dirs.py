#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

import argparse
import copy
import json
import os
import pathlib

from typing import Any, Callable, Dict, List, Optional, cast

from robotnix_common import save, checkout_git, ls_remote, get_mirrored_url, check_free_space, GitCheckoutInfoDict

# A full run took approximately 12 minutes total. Needed to set TMPDIR=/tmp
#
# TODO: Output a timestamp somewhere
# TODO: Optionally parallelize fetching


# Project info is just GitCheckoutInfoDict plus deps
class ProjectInfoDict(GitCheckoutInfoDict, total=False):
    deps: List[str]


def fetch_relpath(dirs: Dict[str, Any], relpath: str, url: str, branch: str) -> ProjectInfoDict:
    orig_url = url
    url = get_mirrored_url(url)

    current_rev = dirs.get(relpath, {}).get('rev', None)
    refs = ls_remote(url)
    ref = f'refs/heads/{branch}'
    if ref not in refs:
        raise ValueError(f'{url} is missing {ref}')
    newest_rev = refs[ref]
    if (current_rev != newest_rev
            or ('path' not in dirs[relpath])
            or (not os.path.exists(dirs[relpath]['path']))):
        dirs[relpath] = checkout_git(url, ref)
        dirs[relpath]['url'] = orig_url
    else:
        print(relpath + ' is up to date.')

    return cast(ProjectInfoDict, dirs[relpath])


# Fetch device source trees for devices in metadata
def fetch_device_dirs(metadata: Any,
                      url_base: str,
                      branch: str,
                      prev_data: Optional[Any] = None,
                      callback: Optional[Callable[[Any], Any]] = None
                      ) -> Dict[str, ProjectInfoDict]:
    dirs: Dict[str, ProjectInfoDict]

    if prev_data is not None:
        dirs = copy.deepcopy(prev_data)
    else:
        dirs = {}

    dirs_to_fetch = set()  # Pairs of (relpath, url)
    dirs_fetched = set()  # Just strings of relpath
    for device, data in metadata.items():
        vendor = data['vendor']
        url = f'{url_base}/android_device_{vendor}_{device}'

        refs = ls_remote(url)
        if f'refs/heads/{branch}' in refs:
            dirs_to_fetch.add((f'device/{vendor}/{device}', url))
        else:
            print(f'SKIP: {branch} branch does not exist for {device}')

    while len(dirs_to_fetch) > 0:
        relpath, url = dirs_to_fetch.pop()
        try:
            dir_info = fetch_relpath(dirs, relpath, url, branch)
        except ValueError:
            continue

        # Also grab any dirs that this one depends on
        lineage_dependencies_filename = os.path.join(dir_info['path'], 'lineage.dependencies')
        if os.path.exists(lineage_dependencies_filename):
            lineage_dependencies = json.load(open(lineage_dependencies_filename))

            for dep in lineage_dependencies:
                if dep['target_path'] not in dirs_fetched:
                    dirs_to_fetch.add((dep['target_path'], f"{url_base}/{dep['repository']}"))

            dir_info['deps'] = [dep['target_path'] for dep in lineage_dependencies]
        else:
            dir_info['deps'] = []

        if callback is not None:
            callback(dirs)
        dirs_fetched.add(relpath)

    return dirs


def fetch_vendor_dirs(metadata: Any,
                      url_base: str,
                      branch: str,
                      prev_data: Optional[Any] = None,
                      callback: Optional[Callable[[Any], Any]] = None
                      ) -> Any:
    required_vendor = set()
    for device, data in metadata.items():
        if 'vendor' in data:
            required_vendor.add(data['vendor'].lower())
        # Bacon needs vendor/oppo
        # https://github.com/danielfullmer/robotnix/issues/26
        if device == 'bacon':
            required_vendor.add('oppo')
        # shamu needs a workaround as well
        if device == 'shamu':
            required_vendor.add('motorola')
            required_vendor.remove('moto')

    if prev_data is not None:
        dirs = copy.deepcopy(prev_data)
    else:
        dirs = {}

    for vendor in required_vendor:
        relpath = f'vendor/{vendor}'

        # XXX: HACK
        if vendor == "xiaomi":
            url = "https://gitlab.com/the-muppets/proprietary_vendor_xiaomi.git/"
        else:
            url = f"{url_base}/proprietary_{relpath.replace('/', '_')}"

        refs = ls_remote(url)
        if f'refs/heads/{branch}' in refs:
            fetch_relpath(dirs, relpath, url, branch)
            if callback is not None:
                callback(dirs)
        else:
            print(f'SKIP: {branch} branch does not exist for {url}')

    return dirs


def main() -> None:
    check_free_space()

    parser = argparse.ArgumentParser()
    parser.add_argument('--branch', help="lineageos version")
    parser.add_argument('product', nargs='*',
                        help='product to fetch directory metadata for, specified by <vendor>_<device> '
                        '(example: google_crosshatch) '
                        'If no products are specified, all products in device-metadata.json will be updated')
    args = parser.parse_args()

    if len(args.product) == 0:
        metadata = json.load(open('device-metadata.json'))
    else:
        metadata = {}
        for product in args.product:
            vendor, device = product.split('_', 1)
            metadata[device] = {'vendor': vendor}

    device_dirs_fn = os.path.join(args.branch, 'device-dirs.json')
    if os.path.exists(device_dirs_fn):
        device_dirs = json.load(open(device_dirs_fn))
    else:
        device_dirs = {}
    fetch_device_dirs(metadata, "https://github.com/LineageOS", args.branch,
                      device_dirs, lambda dirs: save(device_dirs_fn, dirs))

    vendor_dirs_fn = os.path.join(args.branch, 'vendor-dirs.json')
    if os.path.exists(vendor_dirs_fn):
        vendor_dirs = json.load(open(vendor_dirs_fn))
    else:
        vendor_dirs = {}
    fetch_vendor_dirs(metadata, "https://github.com/TheMuppets", args.branch,
                      vendor_dirs, lambda dirs: save(vendor_dirs_fn, dirs))


if __name__ == '__main__':
    os.chdir(pathlib.Path(__file__).parent.resolve())
    main()
