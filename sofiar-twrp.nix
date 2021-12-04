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

let
  inherit (pkgs)
    fetchFromGitHub
  ;
in
{
  device = "sofiar";
  androidVersion = 10;
  flavor = "twrp";
  source.dirs = {
    "kernel/motorola/trinket" = {
      src = fetchFromGitHub {
        owner = "moto-sm6xxx";
        repo = "android_kernel_motorola_trinket";
        rev = "dc06278614038a6569650168dd1099f48fae1ebe";
        sha256 = "0pmls0nxlmb2jbfxngpkdw2i20rrxjq7an8qar8cidhf10sk4mvj";
      };
    };
    "device/motorola/sofiar" = {
      src = fetchFromGitHub {
        owner = "moto-sm6xxx";
        repo = "android_device_motorola_sofiar";
        rev = "ece39f82849b3e50b0a1ebbdc689265abeb7b6e0";
        sha256 = "1x0g63h4ar7zf6dspz339qri7hkxsgzb45h26xk45g48c1sv5wzm";
      };
    };
  };
}
