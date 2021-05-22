#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

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

branch="lineage-18.1"

args=(
    --ref-type branch
    "https://github.com/LineageOS/android"
    "$branch"
    "$branch/repo.json"
)

export TMPDIR=/tmp

./update-device-metadata.py
../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
./update-device-dirs.py --branch "$branch" "${mirror_args[@]}"
