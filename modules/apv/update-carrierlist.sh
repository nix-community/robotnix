#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

nix-prefetch-git https://android.googlesource.com/platform/packages/providers/TelephonyProvider refs/heads/master >latest-telephony-provider.json
