#!/usr/bin/env bash

# This is intended for use with soong-built python programs that include an
# embedded python interpreter.
# These programs include an ELF "launcher" program with an appended ZIP file.
# See also build/soong/python/builder.go. (merge_zips takes a --prepend option
# that refers to this launcher)

# To properly patchelf these files, we split them into parts, patchelf the ELF
# part, and then re-append the ZIP file.

set -euo pipefail

file=$1
interpreter=$2

elfHeader=$(readelf -h "$file")
sectionHeadersOffset=$(echo "$elfHeader" | sed -En "s/Start of section headers:\W+([0-9]*).*$/\1/p")
sectionHeadersSize=$(echo "$elfHeader" | sed -En "s/Size of section headers:\W+([0-9]*).*$/\1/p")
sectionHeadersNum=$(echo "$elfHeader" | sed -En "s/Number of section headers:\W+([0-9]*).*$/\1/p")
offset=$(("$sectionHeadersOffset" + "$sectionHeadersSize" * "$sectionHeadersNum"))

tmpFile=$(mktemp)
trap 'rm $tmpFile' EXIT
cp "$file" "$tmpFile"

dd if="$file" of="$tmpFile" bs=$offset count=1 >/dev/null 2>&1
patchelf --set-interpreter "$interpreter" "$tmpFile"
dd if="$file" of="$tmpFile" bs=$offset skip=1 conv=notrunc oflag=append >/dev/null 2>&1
cp "$tmpFile" "$file"
chmod +x "$file"
