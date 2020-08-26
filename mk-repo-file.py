#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3 nix gitRepo nix-prefetch-git -I nixpkgs=./pkgs

from typing import Optional, Dict
from enum import Enum

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

# The kind of remote a "commitish" refers to.
# These are used for the --ref-type CLI arg.
class ManifestRefType(Enum):
    BRANCH = "heads"
    TAG = "tags"

revHashes: Dict[str, str] = {}
revTrees: Dict[str, str] = {}
treeHashes: Dict[str, str] = {}

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def checkout_git(url, rev):
    print("Checking out %s %s" % (url, rev))
    json_text = subprocess.check_output([ "nix-prefetch-git", "--url", url, "--rev", rev]).decode()
    return json.loads(json_text)

def make_repo_file(url: str, ref: str, filename: str, ref_type: ManifestRefType,
                   override_project_revs: Dict[str, str], force_refresh: bool,
                   mirrors: Dict[str, str]):
    if os.path.exists(filename) and not force_refresh:
        data = json.load(open(filename))
    else:
        print("Fetching information for %s %s" % (url, ref))
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.check_call(['repo', 'init', f'--manifest-url={url}', f'--manifest-branch=refs/{ref_type.value}/{ref}', *REPO_FLAGS], cwd=tmpdir)
            json_text = subprocess.check_output(['repo', 'dumpjson'] + (["--local-only"] if override_project_revs else []), cwd=tmpdir).decode()
            data = json.loads(json_text)

            for project, rev in override_project_revs.items():
                # We have to iterate over the whole output since we don't save
                # the project name anymore, just the relpath, which isn't
                # exactly the project name
                for relpath, p in data.items():
                    if p['url'].endswith(project):
                        p['rev'] = rev

            save(filename, data)

    for relpath, p in data.items():
        if 'sha256' not in p:
            print("Fetching information for %s %s" % (p['url'], p['rev']))
            # Used cached copies if available
            if p['rev'] in revHashes:
                p['sha256'] = revHashes[p['rev']]
                if p['rev'] in revTrees:
                    p['tree'] = revTrees[p['rev']]
                continue

            p_url = p['url']
            for mirror_url, mirror_path in mirrors.items():
                if p['url'].startswith(mirror_url):
                    p_url = p['url'].replace(mirror_url, mirror_path)
                    p['tree'] = subprocess.check_output(['git', 'log','-1', '--pretty=%T', p['rev']], cwd=p_url+'.git').decode().strip()
                    if p['tree'] in treeHashes:
                        p['sha256'] = treeHashes[p['tree']]
                        continue

            # Grab 
            git_info = checkout_git(p_url, p['rev'])
            p['sha256'] = git_info['sha256']

            # Add to cache
            revHashes[p['rev']] = p['sha256']
            if 'tree' in p:
                treeHashes[p['tree']] = p['sha256']

            # Save after every new piece of information just in case we crash
            save(filename, data)

    # Save at the end as well!
    save(filename, data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mirror', action="append", help="a repo mirror to use for a given url, specified by <url>=<path>")
    parser.add_argument('--ref-type', help="the kind of ref that is to be fetched",
                        choices=[t.name.lower() for t in ManifestRefType], default=ManifestRefType.TAG.name.lower())
    parser.add_argument('--force', help="force a re-download. Useful with --ref-type branch", action='store_true')
    parser.add_argument('--repo-prop', help="repo.prop file to use as source for project git revisions")
    parser.add_argument('url', help="manifest URL")
    parser.add_argument('ref', help="manifest ref")
    parser.add_argument('oldrepojson', nargs='*', help="any older repo json files to use for cached sha256s")
    args = parser.parse_args()

    if args.mirror:
        mirrors = dict(mirror.split("=") for mirror in args.mirror)
    else:
        mirrors = {}

    ref_type = ManifestRefType[args.ref_type.upper()]

    # Extract project revisions from repo.prop
    override_project_revs = {}
    if args.repo_prop:
        lines = open(args.repo_prop, 'r').read().split('\n')
        for line in lines:
            if line:
                project, rev = line.split()
                override_project_revs[project] = rev

    # Read all oldrepojson files to populate hashtables
    for filename in args.oldrepojson:
        data = json.load(open(filename))
        for name, p in data.items():
            if 'sha256' in p:
                revHashes[p['rev']] = p['sha256']
                if 'tree' in p:
                    treeHashes[p['tree']] = p['sha256']
                    revTrees[p['rev']] = p['tree']

    filename = f'repo-{args.ref}.json'

    make_repo_file(args.url, args.ref, filename, ref_type, override_project_revs, force_refresh=args.force, mirrors=mirrors)

if __name__ == "__main__":
    main()
