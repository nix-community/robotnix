#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from typing import Any
import json
import urllib.request
import os
import pathlib

from robotnix_common import save


def fetch_metadata(
        lineage_build_targets_url: str = "https://github.com/LineageOS/hudson/raw/master/lineage-build-targets",
        devices_json_url: str = "https://github.com/LineageOS/hudson/raw/master/updater/devices.json"
        ) -> Any:
    metadata = {}

    lineage_build_targets_str = urllib.request.urlopen(lineage_build_targets_url).read().decode()
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

    devices = json.load(urllib.request.urlopen(devices_json_url))
    for data in devices:
        if data['model'] not in metadata:
            continue

        vendor = data['oem']
        vendor = vendor.lower()

        # Workaround name inconsistency with LG
        if vendor == 'lg':
            vendor = 'lge'

        # Workaround google device names source tree inconsistency
        if data['model'] == 'shamu':
            vendor = 'moto'
        if data['model'] == 'flox':
            vendor = 'asus'

        metadata[data['model']].update({
            'vendor': vendor,
            'name': data['name'],
            'lineage_recovery': data.get('lineage_recovery', False)
        })

    return metadata


if __name__ == '__main__':
    metadata = fetch_metadata()
    os.chdir(pathlib.Path(__file__).parent.resolve())
    save('device-metadata.json', metadata)
