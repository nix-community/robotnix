#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

export TMPDIR=/tmp

readarray -t devices < <(jq -r 'keys[]' <kernel-metadata.json)

for device in "${devices[@]}"; do
  args=(
    --ref-type branch
    --cache-search-path ../../../../
    --include-prefix private/                                   # Only get the projects under the private/ path
    --exclude-path private/msm-google-modules/touch/fts/sunfish # Kernel manifest out-of-date, this repo is not tagged for current release.
    --override-tag "$(jq -r ".${device}.tag" <kernel-metadata.json)"
    "https://android.googlesource.com/kernel/manifest"
    "$@"
    "$(jq -r ".${device}.branch" <kernel-metadata.json)"
  )
  echo "### Fetching kernel sources for ${device} ###"
  ../../../../scripts/mk_repo_file.py "${args[@]}"
done
