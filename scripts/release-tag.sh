#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLAVOR=$1

exec git tag -s "$FLAVOR-$(nix eval -f . --arg configuration "{flavor=\"$FLAVOR\";}" --raw config.buildNumber)"
