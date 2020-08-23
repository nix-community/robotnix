#!/usr/bin/env bash

set -eu

args=(
    --mirror "https://android.googlesource.com=/mnt/cache/mirror"
    --ref-type tag
    "https://android.googlesource.com/platform/manifest"
    "$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
