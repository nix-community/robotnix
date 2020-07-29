#!/usr/bin/env bash

export TMPDIR=/tmp
../../mk-repo-file.py --mirror "/mnt/cache/mirror" "https://android.googlesource.com/platform/manifest" "refs/tags/$1" ../*/repo-*.json
