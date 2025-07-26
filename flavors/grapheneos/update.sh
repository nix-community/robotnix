#!/usr/bin/env bash

set -e
set -o pipefail

repo-tool get-graphene-devices -c stable -c beta -c alpha devices.json channel_info.json
tags=$(jq -r .git_tags[] channel_info.json | sort -r)
latest_tag=$(jq -r .git_tags[-1] channel_info.json)

echo Tags to fetch: $tags
for tag in $tags; do
  if [ ! -e $tag.lock ]; then
    echo No lockfile for $tag yet.
    if [ -e $latest_tag.lock ]; then
      echo Copying from latest tag $latest_tag.
      cp $latest_tag.lock $tag.lock
    fi
  fi
  echo Fetching lockfile for tag $tag.
  repo-tool fetch --tag -b $tag https://github.com/GrapheneOS/platform_manifest $tag.lock
  lockfiles="$lockfiles $tag.lock"
done

echo Extracting build IDs...
repo-tool get-build-id build_ids.json $lockfiles

echo Deleting unused lockfiles...
for lockfile in $(ls *.lock); do
	present=0
	for tag in $tags; do
		if [ "$tag.lock" = "$lockfile" ]; then
			present=1
		fi
	done
	if [ $present -eq 0 ]; then
		echo Deleting $lockfile...
		rm "$lockfile"
	fi
done
