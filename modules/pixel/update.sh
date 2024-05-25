#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

curl --fail -s --cookie "devsite_wall_acks=nexus-image-tos" https://developers.google.com/android/images |
  pup "div table tbody tr json{}" |
  jq '.[].children
        | if (length>3)
          then {
             device: (.[2].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[2].children|.[0].href),
             sha256: .[3].text,
          } else {
             device: (.[1].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
          }
          end' | jq -s >pixel-imgs.json

curl --fail -s --cookie "devsite_wall_acks=nexus-ota-tos" https://developers.google.com/android/ota |
  pup "div table tbody tr json{}" |
  jq '.[].children
          | {
             device: (.[1].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-ota-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
            }' | jq -s >pixel-otas.json

curl --fail -s --cookie "devsite_wall_acks=nexus-ota-tos" https://developers.google.com/android/drivers |
  pup "div table tbody tr json{}" |
  jq '.[].children
          | {
             url: (.[2].children|.[0].href),
             sha256: .[3].text,
            }
          | select(.url != null)' | jq -s >pixel-drivers.json

curl --fail -s --cookie "devsite_wall_acks=nexus-ota-tos" https://developer.android.com/about/versions/12/download |
  pup "div table tbody tr json{}" |
  jq '.[].children
          | {
             url: ("https://dl.google.com/developers/android/sc/images/factory/" + (.[1].children|.[0].text)),
             sha256: .[2].children|.[0].text,
            }
          | select(.sha256 != null)' | jq -s >pixel-beta-imgs.json
