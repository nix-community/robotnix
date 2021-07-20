#!/usr/bin/env bash

set -euo pipefail

mypy --exclude apks/chromium .
flake8 --exclude apks/chromium .
shellcheck ./*.sh flavors/*/*.sh modules/pixel/update.sh
