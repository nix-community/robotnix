#!/usr/bin/env bash

set -euo pipefail

shopt -s globstar

cd "$(dirname "${BASH_SOURCE[0]}")/.."

mypy --exclude apks/chromium .
flake8 --exclude apks/chromium .
pytest .
shellcheck ./*.sh flavors/**/*.sh modules/pixel/update.sh scripts/patchelf-prefix.sh pkgs/robotnix/unpack-images.sh
