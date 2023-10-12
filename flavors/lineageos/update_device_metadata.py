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

    # Devices we can't support due to repo naming inconsistencies. If you care
    # about a certain device in this list, you can add a workaround and remove
    # the device from the list.
    ignore = [ 'nx651j' ]

    lineage_build_targets_str = urllib.request.urlopen(lineage_build_targets_url).read().decode()
    for line in lineage_build_targets_str.split("\n"):
        line = line.strip()
        if line == "":
            continue
        if line.startswith("#"):
            continue

        device, variant, branch, updatePeriod = line.split()

        if device not in ignore:
            metadata[device] = {
                'variant': variant,
                'branch': branch,
            }

    ###

    devices = json.load(urllib.request.urlopen(devices_json_url))
    for data in devices:
        if data['model'] not in metadata:
            continue

        workaround_map = {
            # Bacon needs vendor/oppo but is device/oneplus/bacon...
            'bacon' : 'oppo',
            # shamu needs a workaround as well
            'shamu' : 'moto',
            # Workaround google device names source tree inconsistency
            'flox' : 'asus',
            # wade is Google but uses askey vendor dirs? Dynalink is definitely wrong though.
            'wade' : 'askey',
            'deadpool' : 'askey',
            # 10.or is apparently a vendor name. Why TF do you have to put dots in your name.
            # TODO check whether we can exclude this case by always fetching from vendor_device for LOS-20 devices
            'G' : '10or'
        }
        device = data['model']
        vendor = workaround_map[device] if device in workaround_map else data['oem'].lower()

        # Workaround name inconsistency with LG
        if vendor == 'lg':
            vendor = 'lge'
        # Look how cool my name is mom, parenthesis!
        if vendor == 'f(x)tec':
            vendor = 'fxtec'
        # Urgh
        if vendor == '10.or':
            vendor = '10or'
        # Really?
        if vendor == 'banana pi':
            vendor = 'bananapi'

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
