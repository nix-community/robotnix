# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

import json
import os
import subprocess

from unittest.mock import patch
import pytest

from typing import Any, Optional

from robotnix_common import save
import mk_repo_file


def git_create(directory: str, tag: Optional[str] = "release") -> None:
    """Turn a directory into a git repo"""
    cwd = os.getcwd()
    os.chdir(directory)
    subprocess.check_call(["git", "init", "--initial-branch=master"])
    subprocess.check_call(["git", "add", "."])
    subprocess.check_call(["git", "commit", "-m", "Initial Commit"])
    if tag is not None:
        subprocess.check_call(["git", "tag", tag])
    os.chdir(cwd)


@pytest.fixture
def manifest_repo(tmpdir: Any) -> Any:
    repo_top = tmpdir.mkdir("repo")

    manifest_repo = repo_top.mkdir("manifest")
    MANIFEST = \
        '''<?xml version="1.0" encoding="UTF-8"?>
        <manifest>
          <remote name="test" fetch="." />
          <default revision="refs/tags/release" remote="test" />
          <project path="a" name="a" />
          <project path="b" name="b" />
        </manifest>
        '''
    (manifest_repo / "default.xml").write(MANIFEST)
    git_create(manifest_repo)

    a_repo = repo_top.mkdir("a")
    (a_repo / "foo").write("bar")
    git_create(a_repo)

    b_repo = repo_top.mkdir("b")
    (b_repo / "test").write("ing")
    git_create(b_repo)

    return manifest_repo


def test_basic(tmpdir: Any, manifest_repo: Any) -> None:
    os.chdir(tmpdir.mkdir("checkout"))
    mk_repo_file.make_repo_file(manifest_repo, "release", "repo-release.json")
    content = json.load(open('repo-release.json'))
    assert 'a' in content
    assert 'rev' in content['a']
    assert 'sha256' in content['a']
    assert 'url' in content['a']
    assert 'b' in content
    assert 'sha256' in content['b']

    # Removing just one sha256 and resuming
    del content['b']['sha256']
    save('repo-release.json', content)
    with patch('mk_repo_file.ls_remote') as ls_remote:
        ls_remote.side_effect = Exception('Called ls-remote')
        mk_repo_file.make_repo_file(manifest_repo, "release", "repo-release.json", resume=True)
        content = json.load(open('repo-release.json'))
        assert 'sha256' in content['b']
