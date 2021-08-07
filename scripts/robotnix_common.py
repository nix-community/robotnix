# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from typing import Any, Dict

import os
import json
import subprocess


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


def checkout_git(url: str, rev: str, fetch_submodules: bool = False) -> Any:
    print("Checking out %s %s" % (url, rev))
    args = ["nix-prefetch-git", "--url", url, "--rev", rev]
    if fetch_submodules:
        args.append("--fetch-submodules")
    json_text = subprocess.check_output(args).decode()
    return json.loads(json_text)


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
