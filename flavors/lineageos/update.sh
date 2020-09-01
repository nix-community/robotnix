#!/usr/bin/env bash

set -eu

if [[ "$USER" = "danielrf" ]]; then
    mirror_args=(
        --mirror "https://android.googlesource.com=/mnt/cache/mirror"
        --mirror "https://github.com/LineageOS=/mnt/cache/lineageos/LineageOS"
        --mirror "https://github.com/TheMuppets=/mnt/cache/muppets/TheMuppets"
    )
else
    mirror_args=()
fi

args=(
    --ref-type branch
    "https://github.com/LineageOS/android"
    "lineage-17.1"
    ../*/repo-*.json
)

export TMPDIR=/tmp

./update-device-metadata.py
../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
./update-device-dirs.py --resume "${mirror_args[@]}"
