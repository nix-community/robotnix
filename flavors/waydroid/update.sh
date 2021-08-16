#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# https://github.com/WayDroid/anbox-halium/issues/22
#curl -o anbox.xml "https://raw.githubusercontent.com/Anbox-halium/anbox-halium/lineage-17.1/anbox.xml"

args=(
    "https://github.com/LineageOS/android.git"
    "lineage-17.1" # static branch name
    --ref-type branch
    --local-manifest anbox.xml
)

export TMPDIR=/tmp

../../scripts/mk_repo_file.py "${args[@]}"
