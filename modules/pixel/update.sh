#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl go-pup jq

curl --fail -s --cookie "devsite_wall_acks=nexus-image-tos" https://developers.google.com/android/images \
    | pup "div table tbody tr json{}" \
    | jq '.[].children
          | {
             device: (.[1].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
            }' | jq -s > pixel-imgs.json

curl --fail -s --cookie "devsite_wall_acks=nexus-ota-tos" https://developers.google.com/android/ota \
    | pup "div table tbody tr json{}" \
    | jq '.[].children
          | {
             device: (.[1].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-ota-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
            }' | jq -s > pixel-otas.json
