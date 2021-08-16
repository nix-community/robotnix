#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

OUTPUTS=$(./build.sh ./release.nix -A cached --no-out-link "$@")

cachix push robotnix "${OUTPUTS[@]}"
nix copy --to file:///mnt/cache/nix "${OUTPUTS[@]}"
