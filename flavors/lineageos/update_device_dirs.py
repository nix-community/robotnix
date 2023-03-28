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

debug = False

# Project info is just GitCheckoutInfoDict plus deps
class ProjectInfoDict(GitCheckoutInfoDict, total=False):
    deps: List[str]


def fetch_relpath(dirs: Dict[str, Any], relpath: str, url: str, branch: str) -> ProjectInfoDict:
    if debug:
        print(f'Trying to fetch {relpath}')
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
        if debug:
            print(f'Previous data did not contain up-to-date {relpath}, fetching')
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
        if debug:
            print(data)

        # They're google devices but their vendor is askey for some reason
        if device in [ 'deadpool', 'wade' ]:
            vendor = 'askey'
        else:
            vendor = data['vendor']

        # Urgh
        if vendor == '10.or':
            vendor = '10or'

        url = f'{url_base}/android_device_{vendor}_{device}'

        if debug:
            print(url)

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
                      true_branch: str,
                      prev_data: Optional[Any] = None,
                      callback: Optional[Callable[[Any], Any]] = None
                      ) -> Any:
    required_vendor = set()
    for device, data in metadata.items():
        if debug:
            print(device, data)
        if 'vendor' in data:
            workaround_map = {
                # Bacon needs vendor/oppo
                # https://github.com/danielfullmer/robotnix/issues/26
                'bacon' : 'oppo',
                # shamu needs a workaround as well
                'shamu' : 'moto',
                # wade is Google but uses askey vendor dirs? Dynalink is definitely wrong though.
                'wade' : 'askey',
                'deadpool' : 'askey',
                # 10.or is apparently a vendor name. Why TF do you have to put dots in your name.
                # TODO check whether we can exclude this case by always fetching from vendor_device for LOS-20 devices
                'G' : '10or'
            }
            vendor = workaround_map[device] if device in workaround_map else data['vendor']

            if branch == 'lineage-20.0':
                if 'branch' in data and data['branch'] == branch:
                    required_vendor.add(os.path.join(vendor, device))
                else:
                    print(f'SKIP: {device} is not available for {branch}')
            else:
                required_vendor.add(vendor)

    if prev_data is not None:
        dirs = copy.deepcopy(prev_data)
    else:
        dirs = {}

    if debug:
        print(prev_data)
        print(required_vendor)
    for vendor in required_vendor:
        relpath = f'vendor/{vendor}'

        # Only some of google's devices are on gitlab...
        gitlab_vendors = [ 'google/bluejay', 'google/cheetah', 'google/oriole', 'google/panther', 'google/raven' ]
        # Two motorola devices are /not/ on gitlab!
        motorola_gitlab = vendor.startswith('motorola/') and vendor not in [ 'motorola/nio', 'motorola/pstar' ]
        real_url_base = url_base
        if branch == 'lineage-20.0' and (motorola_gitlab or vendor in gitlab_vendors):
            real_url_base = "https://gitlab.com/the-muppets"

        url = f"{real_url_base}/proprietary_{relpath.replace('/', '_')}"

        refs = ls_remote(url)
        if f'refs/heads/{true_branch}' in refs:
            fetch_relpath(dirs, relpath, url, true_branch)
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
    parser.add_argument('--debug', action='store_true', help="print debug info", default=False)
    args = parser.parse_args()

    global debug
    debug = args.debug

    if len(args.product) == 0:
        metadata = json.load(open('device-metadata.json'))
    else:
        metadata = {}
        for product in args.product:
            vendor, device = product.split('_', 1)
            metadata[device] = {'vendor': vendor}

    # Really?
    true_branch = 'lineage-20' if args.branch == 'lineage-20.0' else args.branch

    # device_dirs_fn = os.path.join(args.branch, 'device-dirs.json')
    # if os.path.exists(device_dirs_fn):
    #     device_dirs = json.load(open(device_dirs_fn))
    # else:
    #     device_dirs = {}
    # fetch_device_dirs(metadata, "https://github.com/LineageOS", true_branch,
    #                   device_dirs, lambda dirs: save(device_dirs_fn, dirs))

    vendor_dirs_fn = os.path.join(args.branch, 'vendor-dirs.json')
    if os.path.exists(vendor_dirs_fn):
        vendor_dirs = json.load(open(vendor_dirs_fn))
    else:
        vendor_dirs = {}
    fetch_vendor_dirs(metadata, "https://github.com/TheMuppets", args.branch, true_branch,
                      vendor_dirs, lambda dirs: save(vendor_dirs_fn, dirs))


if __name__ == '__main__':
    os.chdir(pathlib.Path(__file__).parent.resolve())
    main()
