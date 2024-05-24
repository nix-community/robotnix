# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

import json
import os
import subprocess

from unittest.mock import patch
import pytest

from typing import Any, Optional

import mk_repo_file


def git_create(directory: str, tag: Optional[str] = "release", initial_branch: str = "main") -> None:
    """Turn a directory into a git repo"""
    cwd = os.getcwd()
    os.chdir(directory)
    subprocess.check_call(["git", "init", f"--initial-branch={initial_branch}"])
    subprocess.check_call(["git", "config", "--local", "user.name", "testenv"])
    subprocess.check_call(["git", "config", "--local", "user.email", "testenv@example.com"])
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
    # TODO: Each invocation of this downloads a remote git repo to fetch the "repo" tool
    data = mk_repo_file.make_repo_file(manifest_repo, "release")
    assert 'a' in data
    assert 'rev' in data['a']
    assert 'sha256' in data['a']
    assert 'url' in data['a']
    assert 'b' in data
    assert 'sha256' in data['b']

    # Removing just one sha256 and resuming
    del data['b']['sha256']
    with patch('mk_repo_file.ls_remote') as ls_remote:
        ls_remote.side_effect = Exception('Called ls-remote')
        data = mk_repo_file.make_repo_file(manifest_repo, "release", prev_data=data)
        assert 'sha256' in data['b']


def test_read_cached_repo_json(tmpdir: Any) -> None:
    top = tmpdir.mkdir("repo")
    top.mkdir('test_subdir')
    repo_test_filename = top / 'test_subdir' / 'repo-test.json'

    repo_file_contents = {
        'a': {
            'rev': 'foo',
            'tree': 'foo2',
            'dateTime': 1,
            'sha256': 'bar',
            'fetchSubmodules': True,
        },
    }
    repo_test_filename.write(json.dumps(repo_file_contents))

    mk_repo_file.read_cached_repo_json(top)
    assert mk_repo_file.revInfo['foo', True] == {'sha256': 'bar', 'tree': 'foo2', 'dateTime': 1}
    assert mk_repo_file.treeInfo['foo2', True] == {'sha256': 'bar', 'tree': 'foo2', 'dateTime': 1}
