#!/usr/bin/env bash

set -e

#repo-tool get-lineage-devices devices.json

for version in 22.2 22.1 21.0 20.0 19.1 18.1 17.1; do
  mkdir -p lineage-$version
  repo-tool fetch \
	  -b lineage-$version \
	  -l devices.json \
	  --muppets \
	  https://github.com/LineageOS/android \
	  lineage-$version/repo.lock \
	  -m lineage-$version/missing_dep_devices.json
done
