#!/usr/bin/env bash

set -e
set -o pipefail

repo-tool get-graphene-devices -c stable -c beta -c alpha devices.json channel_info.json
tags=$(jq -r .git_tags[] channel_info.json | sort -r)
latest_tag=$(jq -r .git_tags[-1] channel_info.json)

for tag in $tags; do
  if [ ! -e $tag.lock ]; then
    echo No lockfile for $tag yet.
    if [ -e $latest_tag.lock ]; then
      echo Copying from latest tag $latest_tag.
      cp $latest_tag.lock $tag.lock
    fi
  fi
  repo-tool fetch --tag -b $tag https://github.com/GrapheneOS/platform_manifest $tag.lock
  lockfiles="$lockfiles $tag.lock"
done


repo-tool get-build-id build_ids.json $lockfiles
