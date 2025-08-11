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
  repo-tool fetch --tag -r $tag https://github.com/GrapheneOS/platform_manifest $tag.lock
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

echo Prefetching yarn deps for vendor/adevtool...
echo "{" > yarn_hashes.json.part
first=1
for lockfile in $(ls *.lock); do
	if [ $first -eq 1 ]; then
		first=0
	else
		echo "," >> yarn_hashes.json.part
	fi
	adevtool_path=$(jq -r '.entries.["vendor/adevtool"].lock.path' $lockfile)
	echo Ensuring that $adevtool_path is present in the Nix store...
	repo-tool ensure-store-paths $lockfile vendor/adevtool
	echo $lockfile: Prefetching yarn deps in $adevtool_path/yarn.lock
	hash=$(prefetch-yarn-deps $adevtool_path/yarn.lock)
	echo -n "	\"$lockfile\": \"$hash\"" >> yarn_hashes.json.part
done
echo >> yarn_hashes.json.part
echo "}" >> yarn_hashes.json.part
mv yarn_hashes.json.part yarn_hashes.json


echo "Extracting vendor image build IDs..."
for lockfile in $(ls *.lock); do
	git_tag=$(basename -s .lock $lockfile)
	devices=$(jq -r ".device_info.stable | map_values(select(.git_tag == \"$git_tag\")) | keys | .[]" channel_info.json)
	repo-tool ensure-store-paths $lockfile vendor/adevtool
	adevtool_path=$(jq -r '.entries.["vendor/adevtool"].lock.path' $lockfile)
	repo-tool get-graphene-vendor-img-metadata $adevtool_path vendor_img_metadata_$git_tag.json $devices
done
