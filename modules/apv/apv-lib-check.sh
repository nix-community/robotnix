#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

BUILT=$1
UPSTREAM=$2

cd "$BUILT"

check_partition() {
  local partition=$1

  while read -r lib; do
    libdir=$( (readelf -h "$lib" | grep -q ELF64) && echo lib64 || echo lib)

    while read -r required_lib; do
      if [[ ! (-f "$BUILT/$partition/$libdir/$required_lib" || -L "$BUILT/$partition/$libdir/$required_lib") && -e "$UPSTREAM/$partition/$libdir/$required_lib" ]]; then
        echo "$partition/$libdir/$required_lib is needed by $lib"
      fi
    done < <(readelf -d "$lib" | grep NEEDED | tr -s ' ' | cut -d ' ' -f6 | tr -d '[]')
  done < <(find "$partition" -type f -name '*.so')
}

check_partition "system_ext"
check_partition "vendor"
