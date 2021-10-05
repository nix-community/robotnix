# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from unittest.mock import patch
from typing import Any

import update_device_metadata
import update_device_dirs


def test_fetch_metadata(tmp_path: Any) -> None:
    lineage_build_targets = tmp_path / "lineage-build-targets"
    lineage_build_targets.write_text(
        '''# Ignore comments
        crosshatch userdebug lineage-18.1 W
        ''')

    devices_json = tmp_path / "devices.json"
    devices_json.write_text(
        '''[
        {  "model": "crosshatch", "oem": "Google", "name": "Pixel 3 XL", "lineage_recovery": true}
        ]
        ''')

    metadata = update_device_metadata.fetch_metadata(
            f"file://{lineage_build_targets}", f"file://{devices_json}"
    )

    assert metadata == {
        "crosshatch": {
            "branch": "lineage-18.1",
            "lineage_recovery": True,
            "name": "Pixel 3 XL",
            "variant": "userdebug",
            "vendor": "google"
        },
    }


@patch("update_device_dirs.checkout_git")
@patch("update_device_dirs.ls_remote")
def test_fetch_device_dirs(ls_remote: Any, checkout_git: Any, tmpdir: Any) -> None:
    baseurl = 'BASEURL'

    ls_remote_dict = {
        f'{baseurl}/android_device_google_crosshatch': {'refs/heads/lineage-18.1': '12345'},
        f'{baseurl}/android_kernel_google_msm-4.9': {'refs/heads/lineage-18.1': '67890'}
    }
    ls_remote.side_effect = lambda url: ls_remote_dict[url]

    fake_dir = tmpdir.mkdir('android_device_google_crosshatch')
    (fake_dir / "lineage.dependencies").write(
        '''[
            {
                "repository": "android_kernel_google_msm-4.9",
                "target_path": "kernel/google/msm-4.9"
            }
        ]'''
    )
    checkout_git_dict = {
        (f'{baseurl}/android_device_google_crosshatch', 'refs/heads/lineage-18.1'):
        {
            "date": "2021-07-12T10:07:57-05:00",
            "deepClone": False,
            "deps": [
                "packages/apps/ElmyraService"
            ],
            "fetchSubmodules": False,
            "leaveDotGit": False,
            "path": fake_dir,
            "rev": "0000000000ca33df352b45a4241c353b6a52ec7d",
            "sha256": "00000000000aamp6w094ingaccr9cx6d6zi1wb9crmh4r7b19b1f",
            "url": f"{baseurl}/android_device_google_crosshatch"
        },
        (f'{baseurl}/android_kernel_google_msm-4.9', 'refs/heads/lineage-18.1'):
        {
            "date": "2021-07-12T10:07:57-05:00",
            "deepClone": False,
            "fetchSubmodules": False,
            "leaveDotGit": False,
            "path": tmpdir.mkdir('empty'),
            "rev": "0000000000ca33df352b45a4241c353b6a52ec7d",
            "sha256": "00000000000aamp6w094ingaccr9cx6d6zi1wb9crmh4r7b19b1f",
            "url": f"{baseurl}/android_kernel_google_msm-4.9"
        },
    }
    checkout_git.side_effect = lambda url, rev: checkout_git_dict[url, rev]

    metadata = {
        "crosshatch": {
            "branch": "lineage-18.1",
            "lineage_recovery": True,
            "name": "Pixel 3 XL",
            "variant": "userdebug",
            "vendor": "google"
        },
    }
    dirs = update_device_dirs.fetch_device_dirs(metadata, baseurl, 'lineage-18.1')

    assert 'device/google/crosshatch' in dirs


@patch("update_device_dirs.checkout_git")
@patch("update_device_dirs.ls_remote")
def test_fetch_vendor_dirs(ls_remote: Any, checkout_git: Any, tmpdir: Any) -> None:
    baseurl = 'BASEURL'
    ls_remote_dict = {
        'BASEURL/proprietary_vendor_google': {'refs/heads/lineage-18.1': '12345'},
    }
    ls_remote.side_effect = lambda url: ls_remote_dict[url]

    checkout_git_dict = {
        ('BASEURL/proprietary_vendor_google', 'refs/heads/lineage-18.1'):
        {
            "date": "2021-07-12T10:07:57-05:00",
            "deepClone": False,
            "fetchSubmodules": False,
            "leaveDotGit": False,
            "path": 'foobar',
            "rev": "0000000000ca33df352b45a4241c353b6a52ec7d",
            "sha256": "00000000000aamp6w094ingaccr9cx6d6zi1wb9crmh4r7b19b1f",
            "url": "BASEURL/proprietary_vendor_google"
        },
    }
    checkout_git.side_effect = lambda url, rev: checkout_git_dict[url, rev]

    metadata = {
        "crosshatch": {
            "branch": "lineage-18.1",
            "lineage_recovery": True,
            "name": "Pixel 3 XL",
            "variant": "userdebug",
            "vendor": "google"
        },
    }
    dirs = update_device_dirs.fetch_vendor_dirs(metadata, baseurl, 'lineage-18.1')

    assert 'vendor/google' in dirs
