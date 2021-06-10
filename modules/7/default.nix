# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf;
in

mkIf (config.androidVersion == 7)
{
  apiLevel = 25; # Assumes 7.1
}
