#!/usr/bin/env bash

export TMPDIR=/tmp
../../mk-repo-file.py --mirror "/mnt/cache/mirror" "https://github.com/GrapheneOS/platform_manifest" "refs/tags/$1" repo-*.json ../vanilla/repo-*.json
