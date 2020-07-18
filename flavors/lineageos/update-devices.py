#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3 nix-prefetch-git -I nixpkgs=../../pkgs

import argparse
import json
import os
import subprocess
import urllib.request

# A full run took approximately 12 minutes total. Needed to set TMPDIR=/tmp
#
# TODO: Output a timestamp somewhere
# TODO: Extract code shared with mk-repo-file.py into a common location
#
# 369 seconds so far

LINEAGE_REPO_BASE = "https://github.com/LineageOS/"
VENDOR_REPO_BASE = "https://github.com/TheMuppets/"
BRANCH = "lineage-17.1"

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def newest_rev(url):
    remote_info = subprocess.check_output([ "git", "ls-remote", url, 'refs/heads/' + BRANCH ]).decode()
    remote_rev = remote_info.split('\t')[0]
    return remote_rev

def checkout_git(url, rev):
    print("Checking out %s %s" % (url, rev))
    json_text = subprocess.check_output([ "nix-prefetch-git", "--url", url, "--rev", rev]).decode()
    return json.loads(json_text)

def fetch_metadata(filename):
    metadata = {}

    lineage_build_targets_str = urllib.request.urlopen("https://github.com/LineageOS/hudson/raw/master/lineage-build-targets").read().decode()
    for line in lineage_build_targets_str.split("\n"):
        line = line.strip()
        if line == "":
            continue
        if line.startswith("#"):
            continue

        device, variant, branch, updatePeriod = line.split()
        metadata[device] = {
            'variant': variant,
            'branch': branch,
        }

    ###

    devices = json.load(urllib.request.urlopen("https://github.com/LineageOS/hudson/raw/master/updater/devices.json"))
    for data in devices:
        if data['model'] not in metadata:
            continue

        metadata[data['model']].update({
            'oem': data['oem'],
            'name': data['name'],
            'lineage_recovery': data.get('lineage_recovery', False)
        })

    ###

    device_deps = json.load(urllib.request.urlopen("https://github.com/LineageOS/hudson/raw/master/updater/device_deps.json"))
    for model, deps in device_deps.items():
        if model not in metadata:
            continue

        metadata[model].update({'deps': deps})

    ###

    save(filename, metadata)
    return metadata

def fetch_dirs(metadata, filename, resume=False):
    required_deps = set()
    for device, data in metadata.items():
        if data['branch'] == BRANCH:
            if 'deps' in data:
                required_deps.update(data['deps'])

    if resume and os.path.exists(filename):
        dirs = json.load(open(filename))
    else:
        dirs = {}

    for dep in required_deps:
        if dep.startswith('android_'):
            relpath = dep[8:]
        relpath = relpath.replace('_', '/')

        url = LINEAGE_REPO_BASE + dep

        current_rev = dirs.get(relpath, {}).get('rev', None)
        if current_rev != newest_rev(url):
            dirs[relpath] = checkout_git(url, 'refs/heads/' + BRANCH)
            save(filename, dirs) # Save after every step, for resuming
        else:
            print(relpath + ' is up to date.')

    save(filename, dirs)
    return dirs

def fetch_vendor_dirs(metadata, filename, resume):
    required_oems = set()
    for device, data in metadata.items():
        if data['branch'] == BRANCH:
            if 'oem' in data:
                required_oems.add(data['oem'].lower())

    if resume and os.path.exists(filename):
        dirs = json.load(open(filename))
    else:
        dirs = {}

    for oem in required_oems:
        # XXX: Naming hack. Ensure .nix has it too
        if oem == 'lg':
            oem = 'lge'

        relpath = "vendor/" + oem

        # XXX: HACK
        if oem == "xiaomi":
            url = "https://gitlab.com/the-muppets/proprietary_vendor_xiaomi.git/"
        else:
            url = VENDOR_REPO_BASE + 'proprietary_' + relpath.replace('/', '_')

        current_rev = dirs.get(relpath, {}).get('rev', None)
        if current_rev != newest_rev(url):
            dirs[relpath] = checkout_git(url, 'refs/heads/' + BRANCH)
            save(filename, dirs) # Save after every step, for resuming
        else:
            print(relpath + ' is up to date.')


    save(filename, dirs)
    return dirs

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--resume', action='store_true', help='use existing device-dirs.json file as source for hashes')
    args = parser.parse_args()

    metadata = fetch_metadata('device-metadata.json')
    device_dirs = fetch_dirs(metadata, 'device-dirs.json', args.resume)
    vendor_dirs = fetch_vendor_dirs(metadata, 'vendor-dirs.json', args.resume)


if __name__ == '__main__':
    main()
