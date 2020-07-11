#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3 nix gitRepo nix-prefetch-git -I nixpkgs=./pkgs

from typing import Optional, Dict

import argparse
import json
import os
import subprocess
import tempfile

REPO_FLAGS = [
    "--quiet",
    "--repo-url=https://github.com/danielfullmer/tools_repo",
    "--repo-branch=master",
    "--no-repo-verify",
    "--depth=1",
]

AOSP_BASEURL = "https://android.googlesource.com"

revHashes: Dict[str, str] = {}
revTrees: Dict[str, str] = {}
treeHashes: Dict[str, str] = {}

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def checkout_git(url, rev):
    print("Checking out %s %s" % (url, rev))
    json_text = subprocess.check_output([ "nix-prefetch-git", "--url", url, "--rev", rev]).decode()
    return json.loads(json_text)

def make_repo_file(url: str, ref: str, filename: str, force_refresh: bool, mirror: Optional[str]=None):
    if os.path.exists(filename) and not force_refresh:
        data = json.load(open(filename))
    else:
        print("Fetching information for %s %s" % (url, ref))
        with tempfile.TemporaryDirectory() as tmpdir:
            json_text = subprocess.check_output(['repo', 'dumpjson'], cwd=tmpdir).decode()
            open(filename, 'w').write(json_text)
            subprocess.check_call(['repo', 'init', '--manifest-url=' + url, '--manifest-branch=' + ref, *REPO_FLAGS], cwd=tmpdir)
            data = json.loads(json_text)

    for relpath, p in data.items():
        if 'sha256' not in p:
            print("Fetching information for %s %s" % (p['url'], p['rev']))
            # Used cached copies if available
            if p['rev'] in revHashes:
                p['sha256'] = revHashes[p['rev']]
                if p['rev'] in revTrees:
                    p['tree'] = revTrees[p['rev']]
                continue

            if mirror and p['url'].startswith(AOSP_BASEURL):
                p_url = p['url'].replace(AOSP_BASEURL, mirror)
                p['tree'] = subprocess.check_output(['git', 'log','-1', '--pretty=%T', p['rev']], cwd=p_url+'.git').decode().strip()
                if p['tree'] in treeHashes:
                    p['sha256'] = treeHashes[p['tree']]
                    continue
            else:
                p_url = p['url']

            # Grab 
            git_info = checkout_git(p_url, p['rev'])
            p['sha256'] = git_info['sha256']

            # Add to cache
            revHashes[p['rev']] = p['sha256']
            if mirror and p['url'].startswith(AOSP_BASEURL):
                treeHashes[p['tree']] = p['sha256']

            # Save after every new piece of information just in case we crash
            save(filename, data)

    # Save at the end as well!
    save(filename, data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mirror', help="path to a repo mirror of %s" % AOSP_BASEURL)
    parser.add_argument('--force', help="force a re-download. Useful with --ref-type branch", action='store_true')
    parser.add_argument('url', help="manifest URL")
    parser.add_argument('ref', help="manifest ref")
    parser.add_argument('oldrepojson', nargs='*', help="any older repo json files to use for cached sha256s")
    args = parser.parse_args()

    # Read all oldrepojson files to populate hashtables
    for filename in args.oldrepojson:
        data = json.load(open(filename))
        for name, p in data.items():
            if 'sha256' in p:
                revHashes[p['rev']] = p['sha256']
                if 'tree' in p:
                    treeHashes[p['tree']] = p['sha256']
                    revTrees[p['rev']] = p['tree']

    if args.ref.startswith('refs/tags/'):
        ref = args.ref[len('refs/tags/'):]
    else:
        ref= args.ref
    filename = f'repo-{ref}.json'

    make_repo_file(args.url, args.ref, filename, force_refresh=args.force, mirror=args.mirror)

if __name__ == "__main__":
    main()
