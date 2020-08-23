#!/usr/bin/env bash

set -eu

mirror_args=(
    --mirror "https://android.googlesource.com=/mnt/cache/mirror"
    --mirror "https://github.com/LineageOS=/mnt/cache/lineageos/LineageOS"
    --mirror "https://github.com/TheMuppets=/mnt/cache/muppets/TheMuppets"
)

args=(
    --ref-type branch
    "https://github.com/LineageOS/android"
    "$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
