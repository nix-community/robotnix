#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

export TMPDIR=/tmp

args=(
    --cache-search-path ../../../
    --ref-type tag
    --out "repo-${DEVICE_FAMILY}-${TAG}.json"
    "https://github.com/GrapheneOS/kernel_manifest-${DEVICE_FAMILY}"
    "${TAG}"
    "$@"
)

../../../scripts/mk_repo_file.py "${args[@]}"
