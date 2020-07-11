#!/usr/bin/env bash

export TMPDIR=/tmp
../../mk-repo-file.py --mirror "/mnt/media/mirror" "https://github.com/GrapheneOS/platform_manifest" "$1" repo-*.json ../vanilla/repo-*.json
