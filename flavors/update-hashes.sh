#!/usr/bin/env bash

# Run this from the root directory like: ./flavors/update-hashes.sh

$(nix-build ./modules/source/update-hashes.nix --no-out-link) ./flavors/hashes.json $(nix-build ./flavors/jsonFiles.nix --no-out-link | sort | uniq) || exit 1

# Can also run this as well;
#$(nix-build ./modules/source/clean-hashes.nix --no-out-link)  ./flavors/hashes.json $(nix-build ./flavors/jsonFiles.nix --no-out-link | sort | uniq)
