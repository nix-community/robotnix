#!/usr/bin/env bash

set -eu

args=(
    --mirror "/mnt/media/mirror"
    --ref-type branch
    "https://android.googlesource.com/platform/manifest"
    "refs/tags/$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
