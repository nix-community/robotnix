#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3 nix-prefetch-git -I nixpkgs=../../pkgs

import argparse
import json
import subprocess

# TODO: Combine with mk-repo-file.py
def checkout_git(url, rev):
    print("Checking out %s %s" % (url, rev))
    json_text = subprocess.check_output([ "nix-prefetch-git", "--url", url, "--rev", rev]).decode()
    return json.loads(json_text)

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mirror', action="append", help="a repo mirror to use for a given url, specified by <url>=<path>")
    args = parser.parse_args()

    if args.mirror:
        mirrors = dict(mirror.split("=") for mirror in args.mirror)
    else:
        mirrors = {}

    data = json.load(open('kernel-metadata.json'))
    outhashes = {}
    for tag, repos in data.items():
        for repo_name, repo_relpath in repos.items():
            orig_url = f"https://android.googlesource.com/{repo_name}"

            url = orig_url
            for mirror_url, mirror_path in mirrors.items():
                if url.startswith(mirror_url):
                    url = url.replace(mirror_url, mirror_path)

            git_data = checkout_git(url, tag)
            git_data['url'] = orig_url

            if tag not in outhashes:
                outhashes[tag] = {}
            outhashes[tag][orig_url] = git_data

            save('kernel-hashes.json', outhashes)

    save('kernel-hashes.json', outhashes)

if __name__ == "__main__":
    main()
