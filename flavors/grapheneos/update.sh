#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

../../modules/apv/update-carrierlist.sh

_KERNEL_PREFIX=${KERNEL_PREFIX:-kernel/google}

args=(
    --cache-search-path ../../
    --ref-type tag
    --project-fetch-submodules "${_KERNEL_PREFIX}/crosshatch"
    --project-fetch-submodules "${_KERNEL_PREFIX}/coral"
    --project-fetch-submodules "${_KERNEL_PREFIX}/sunfish"
    --project-fetch-submodules "${_KERNEL_PREFIX}/redbull"
    --project-fetch-submodules "${_KERNEL_PREFIX}/barbet"
    --project-fetch-submodules "${_KERNEL_PREFIX}/raviole"
    --project-fetch-submodules "${_KERNEL_PREFIX}/bluejay"
    --project-fetch-submodules "${_KERNEL_PREFIX}/pantah"
    "https://github.com/GrapheneOS/platform_manifest"
    "$@"
)

export TMPDIR=/tmp

../../scripts/mk_repo_file.py "${args[@]}"
