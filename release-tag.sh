#!/usr/bin/env bash

FLAVOR=$1

exec git tag -s $FLAVOR-$(nix eval -f . --arg configuration "{flavor=\"$FLAVOR\";}" --raw config.buildNumber)
