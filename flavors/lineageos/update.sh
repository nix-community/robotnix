#!/usr/bin/env bash

set -e
set -u

args=(
    --mirror "/mnt/media/mirror"
    --ref-type branch
    "https://github.com/LineageOS/android"
    "$@"
    *.json #../vanilla/*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
