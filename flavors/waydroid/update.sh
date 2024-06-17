#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# https://docs.waydro.id/development/compile-waydroid-lineage-os-based-images
repo_tmp="$(mktemp -d)"
pushd "${repo_tmp}"
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1
wget -O - https://raw.githubusercontent.com/waydroid/android_vendor_waydroid/lineage-17.1/manifest_scripts/generate-manifest.sh | bash
popd

args=(
  "https://github.com/LineageOS/android.git"
  "lineage-17.1" # static branch name
  --ref-type branch
)

for manifest in "${repo_tmp}"/.repo/local_manifests/*.xml; do
  args+=(--local-manifest "${manifest}")
done

export TMPDIR=/tmp

../../scripts/mk_repo_file.py "${args[@]}"
