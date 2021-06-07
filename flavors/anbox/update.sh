#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Samuel Dionne-Riel
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -eu

if [[ "$USER" = "danielrf" ]]; then
    mirror_args=(
        --mirror "https://android.googlesource.com=/mnt/cache/mirror"
        --mirror "https://github.com/anbox=/mnt/cache/anbox/anbox"
    )
else
    mirror_args=()
fi

args=(
	"https://github.com/anbox/platform_manifests"
    --ref-type branch
    "anbox" # static branch name
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
