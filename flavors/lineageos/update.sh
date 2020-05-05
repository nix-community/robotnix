#!/usr/bin/env bash

set -e
set -u

args=(
	#--mirror "/mnt/media/mirror"
	"https://github.com/LineageOS/android"
	"$1"
	*.json #../vanilla/*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
