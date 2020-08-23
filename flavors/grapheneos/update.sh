#!/usr/bin/env bash


set -eu

args=(
    --mirror "/mnt/cache/mirror"
    --ref-type tag
    "https://github.com/GrapheneOS/platform_manifest"
    "$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
