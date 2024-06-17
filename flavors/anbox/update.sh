#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Samuel Dionne-Riel
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

args=(
  --cache-search-path ../../
  --ref-type branch
  "https://github.com/pmanbox/platform_manifests"
  "pmanbox" # static branch name
)

export TMPDIR=/tmp

../../scripts/mk_repo_file.py "${args[@]}"
