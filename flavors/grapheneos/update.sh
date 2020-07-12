#!/usr/bin/env bash


set -eu

args=(
    --mirror "/mnt/media/mirror"
    --ref-type branch
    "https://github.com/GrapheneOS/platform_manifest"
    "refs/tags/$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
