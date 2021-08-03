#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

branch=$1

args=(
    --ref-type branch
    "https://github.com/LineageOS/android"
    "$branch"
    */repo*.json
)

export TMPDIR=/tmp

./update-device-metadata.py
../../scripts/mk-repo-file.py --out "${branch}/repo.json" "${args[@]}"
./update-device-dirs.py --branch "$branch"
