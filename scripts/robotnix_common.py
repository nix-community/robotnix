# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from typing import Any

import json
import subprocess


def save(filename: str, data: Any) -> None:
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))


def checkout_git(url: str, rev: str, fetch_submodules: bool = False) -> Any:
    print("Checking out %s %s" % (url, rev))
    args = ["nix-prefetch-git", "--url", url, "--rev", rev]
    if fetch_submodules:
        args.append("--fetch-submodules")
    json_text = subprocess.check_output(args).decode()
    return json.loads(json_text)


def ls_remote(url: str, rev: str) -> str:
    remote_info = subprocess.check_output(["git", "ls-remote", url, rev]).decode()
    remote_rev = remote_info.split('\t')[0]
    assert remote_rev != ""
    return remote_rev
