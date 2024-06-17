#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

branch=$1

args=(
  --cache-search-path ../../
  --ref-type branch
  "https://github.com/LineageOS/android"
  "$branch"
)

export TMPDIR=/var/tmp

./update_device_metadata.py
../../scripts/mk_repo_file.py --out "${branch}/repo.json" "${args[@]}"
./update_device_dirs.py --branch "$branch"

endEpoch="$(date +%s)"
echo "$endEpoch" >lastUpdated.epoch
echo Updated branch "$branch". End epoch: "$endEpoch"
