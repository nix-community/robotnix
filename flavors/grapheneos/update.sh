#!/usr/bin/env bash

set -e
set -o pipefail

repo-tool get-graphene-devices -c stable -c beta -c alpha devices.json channel_info.json
tags=$(jq -r .git_tags[] channel_info.json | sort -r)
latest_tag=$(jq -r .git_tags[-1] channel_info.json)

echo Tags to fetch: $tags
for tag in $tags; do
  mkdir -p $tag
  if [ ! -e $tag/repo.lock ]; then
    echo No lockfile for $tag yet.
    if [ -e $latest_tag/repo.lock ]; then
      echo Copying from latest tag $latest_tag.
      cp -r $latest_tag/repo.lock $tag/repo.lock
    fi
  fi
  echo Fetching lockfile for tag $tag.
  repo-tool fetch --tag -r $tag https://github.com/GrapheneOS/platform_manifest $tag/repo.lock
  lockfiles="$lockfiles $tag/repo.lock"
done

echo Extracting build IDs...
repo-tool get-build-id build_ids.json $lockfiles

echo Deleting unused lockfiles...
for lockfile in $(ls */repo.lock); do
  present=0
  for tag in $tags; do
    if [ "$tag/repo.lock" = "$lockfile" ]; then
      present=1
    fi
  done
  if [ $present -eq 0 ]; then
    echo Deleting $lockfile...
    rm -r $(dirname $lockfile)
  fi
done

echo Prefetching yarn deps for vendor/adevtool...
echo "{" >yarn_hashes.json.part
first=1
for tag in $tags; do
  if [ $first -eq 1 ]; then
    first=0
  else
    echo "," >>yarn_hashes.json.part
  fi
  adevtool_path=$(jq -r '.entries.["vendor/adevtool"].lock.path' $tag/repo.lock)
  echo Ensuring that $adevtool_path is present in the Nix store...
  repo-tool ensure-store-paths $tag/repo.lock vendor/adevtool
  echo $tag: Prefetching yarn deps in $adevtool_path/yarn.lock
  hash=$(prefetch-yarn-deps $adevtool_path/yarn.lock)
  echo -n "	\"$tag\": \"$hash\"" >>yarn_hashes.json.part
done
echo >>yarn_hashes.json.part
echo "}" >>yarn_hashes.json.part
mv yarn_hashes.json.part yarn_hashes.json

for tag in $tags; do
  mkdir -p $tag/vendor_imgs/
  nix build --impure --expr "import ./adevtool-show-metadata-json.nix \"$tag\"" --out-link result-adevtool
  devices=$(jq -r ".[]" devices.json)
  orig_dir=$(pwd)
  cd result-adevtool
  for device in $devices; do
    found=0
    for channel in stable beta alpha; do
      if [ $tag = $(jq -r .device_info.$channel.$device.git_tag $orig_dir/channel_info.json) ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 1 ]; then
      echo "Extracting vendor image metadata for $tag $device..."
      vendor/adevtool/bin/run generate-all -d $device >$orig_dir/$tag/vendor_imgs/$device.json
    fi
  done
  cd $orig_dir
done
