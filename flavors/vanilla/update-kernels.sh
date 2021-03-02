#!/usr/bin/env bash

set -eu

if [[ "$USER" = "danielrf" ]]; then
    mirror_args=(
        --mirror "https://android.googlesource.com=/mnt/cache/mirror"
    )
else
    mirror_args=()
fi

export TMPDIR=/tmp

readarray -t devices < <(jq -r 'keys[]' <kernel-metadata.json)

for device in "${devices[@]}"; do
    args=(
        --ref-type branch
        --force
        --include-prefix private/ # Only get the projects under the private/ path
        --override-tag "$(jq -r ".${device}.tag" < kernel-metadata.json)"
        "https://android.googlesource.com/kernel/manifest"
        "$@"
        "$(jq -r ".${device}.branch" < kernel-metadata.json)"
        ../*/repo-*.json
    )
    echo "### Fetching kernel sources for ${device} ###"
    ../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
done
