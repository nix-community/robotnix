#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

if command -v nproc >/dev/null 2>&1; then
  cores="$(nproc)"
else
  cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
fi

nix-build --option extra-sandbox-paths "/keys=/var/secrets/android-keys /var/cache/ccache?" -j4 --cores "$cores" "$@"
