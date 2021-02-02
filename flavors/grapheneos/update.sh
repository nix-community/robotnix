#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -eu

if [[ "$USER" = "danielrf" ]]; then
    mirror_args=(
        --mirror "https://android.googlesource.com=/mnt/cache/mirror"
    )
else
    mirror_args=()
fi

args=(
    --mirror "https://android.googlesource.com=/mnt/cache/mirror"
    --ref-type tag
    "https://github.com/GrapheneOS/platform_manifest"
    "$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
