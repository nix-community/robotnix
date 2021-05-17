#!/usr/bin/env nix-shell
#!nix-shell -i bash -p simg2img e2fsprogs
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# Downloads and extracts the BUILD_DATETIME from a factory image
# As of 2021-05-08, all upstream device builds share the same BUILD_DATETIME,
# so just using redfin here.

set -euo pipefail

BUILD_NUMBER=$1
DEVICE=redfin
FACTORY_IMG=${DEVICE}-factory-${BUILD_NUMBER}

tmp_dir=$(mktemp -d)
pushd "${tmp_dir}" >/dev/null
trap 'rm -rf ${tmp_dir}' EXIT

curl -O "https://releases.grapheneos.org/${FACTORY_IMG}.zip"
bsdtar xf "${FACTORY_IMG}.zip"
cd "${FACTORY_IMG}"
bsdtar xf "image-${DEVICE}-${BUILD_NUMBER}.zip"
simg2img system.img system.raw
debugfs system.raw -R "dump system/build.prop build.prop"
BUILD_DATETIME=$(grep ro.build.date.utc build.prop | cut -d= -f2)

popd >/dev/null

echo "{ buildNumber = \"${BUILD_NUMBER}\"; buildDateTime = ${BUILD_DATETIME}; }" > upstream-params.nix
