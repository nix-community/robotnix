#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl go-pup jq

curl --fail -s https://developers.google.com/android/images \
    | pup "div table tbody tr json{}" \
    | jq ".[].children
          | {
             device: (.[1].children|.[0].\"data-label\"|split(\" \")|.[0]),
             label: (.[1].children|.[0].\"data-label\"),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
            }" | jq -s > pixel.json
