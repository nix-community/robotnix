#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

SKIP_REPO_FILE=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-mk-repo-file|-s)
            SKIP_REPO_FILE=1
            ;;
        --)
            shift
            branch="$1"
            break
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            branch="$1"
            ;;
    esac
    shift
done

cd "$(dirname "${BASH_SOURCE[0]}")"

args=(
    --cache-search-path ../../
    --ref-type branch
    "https://github.com/LineageOS/android"
    "$branch"
)

export TMPDIR=/var/tmp

./update_device_metadata.py
if [[ -z "$SKIP_REPO_FILE" ]]; then
  ../../scripts/mk_repo_file.py --out "${branch}/repo.json" "${args[@]}"
fi
./update_device_dirs.py --branch "$branch"

endEpoch="$(date +%s)"
echo "$endEpoch" > $branch/lastUpdated.epoch
echo Updated branch "$branch". End epoch: "$endEpoch"
