#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

../../modules/apv/update-carrierlist.sh

args=(
  --cache-search-path ../../
  --ref-type tag
  "https://github.com/GrapheneOS/platform_manifest"
  --project-fetch-submodules "kernel/google/crosshatch"
  --project-fetch-submodules "kernel/google/coral"
  --project-fetch-submodules "kernel/google/sunfish"
  --project-fetch-submodules "kernel/google/redbull"
  --project-fetch-submodules "kernel/google/barbet"
  "$@"
)

export TMPDIR=/tmp

../../scripts/mk_repo_file.py "${args[@]}"
