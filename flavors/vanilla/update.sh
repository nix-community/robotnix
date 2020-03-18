#!/usr/bin/env bash

export TMPDIR=/tmp
../../mk-repo-file.py --mirror "/mnt/media/mirror" "https://android.googlesource.com/platform/manifest" "$1" *.json #../grapheneos/*.json
