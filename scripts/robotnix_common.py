# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from typing import Any, Dict, TypedDict, cast

import json
import os
import subprocess
import sys


ROBOTNIX_GIT_MIRRORS = os.environ.get('ROBOTNIX_GIT_MIRRORS', '')
if ROBOTNIX_GIT_MIRRORS:
    MIRRORS: Dict[str, str] = dict(
            (mirror.split("=")[0], mirror.split("=")[1])
            for mirror in ROBOTNIX_GIT_MIRRORS.split('|')
            )
else:
    MIRRORS = {}


def get_mirrored_url(url: str) -> str:
    for mirror_url, mirror_path in MIRRORS.items():
        if url.startswith(mirror_url):
            url = url.replace(mirror_url, mirror_path)
    return url


def save(filename: str, data: Any) -> None:
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def get_store_path(path):
    """Get actual path to a Nix store path; supports handling local remotes"""
    prefix = os.getenv("NIX_REMOTE", "")
    if prefix and not prefix.startswith("/"):
        raise Exception("Must be run on a local Nix store.")

    return f"{prefix}/{path}"


class GitCheckoutInfoDict(TypedDict):
    """Container for output from nix-prefetch-git"""
    url: str
    rev: str
    date: str
    path: str
    sha256: str
    fetchSubmodules: str
    deepClone: str
    leaveDotGit: str


def checkout_git(
    url: str,
    rev: str,
    fetch_submodules: bool = False,
    fetch_lfs: bool = False,
) -> GitCheckoutInfoDict:
    print("Checking out %s %s" % (url, rev))
    args = ["nix-prefetch-git", "--url", url, "--rev", rev]
    if fetch_submodules:
        args.append("--fetch-submodules")
    if fetch_lfs:
        args.append("--fetch-lfs")
    json_text = subprocess.check_output(args).decode()
    return cast(GitCheckoutInfoDict, json.loads(json_text))


def check_free_space() -> None:
    # nix-prefetch-git will check out under $TMPDIR (if it exists), or /tmp (otherwise)
    path = os.environ['TMPDIR'] if 'TMPDIR' in os.environ else '/tmp'

    st = os.statvfs(path)
    free_bytes = st.f_bavail * st.f_bsize

    desired_gb = 10
    if free_bytes < (desired_gb * 1024**3):
        print(f"WARNING: You have less than {desired_gb} GiB free under {path}.\n" +
              f"This script might fail if a checked-out repository is larger than {desired_gb} GiB.\n" +
              "Either free space at this location or set the TMPDIR environment variable " +
              "to a path which has enough free space.",
              file=sys.stderr
              )


REMOTE_REFS: Dict[str, Dict[str, str]] = {}  # url: { ref: rev }


def ls_remote(url: str) -> Dict[str, str]:
    if url in REMOTE_REFS:
        return REMOTE_REFS[url]

    orig_url = url
    url = get_mirrored_url(url)

    remote_info = subprocess.check_output(["git", "ls-remote", url]).decode()
    REMOTE_REFS[orig_url] = {}
    for line in remote_info.split('\n'):
        if line:
            ref, rev = reversed(line.split('\t'))
            REMOTE_REFS[orig_url][ref] = rev
    return REMOTE_REFS[orig_url]
