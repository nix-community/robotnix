# SPDX-FileCopyrightText: 2021 Samuel Dionne-Riel
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

#
# Usage
# =====
#
# ```
# $ nix-build --arg configuration ./sofiar-twrp.nix -A config.build.twrp
# ```
#

{ config, pkgs, lib, ... }:

{
  device = "surfna";
  androidVersion = 9;
  flavor = "twrp";
  source.dirs = {
    "device/motorola/surfna" = {
      src = builtins.fetchGit ~/tmp/TWRP/android_device_motorola_surfna;
    };
  };
}
