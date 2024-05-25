# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkIf mkDefault;

  flex = pkgs.callPackage ./flex-2.5.39.nix { };
in
mkIf (config.androidVersion == 9) {
  # Some android version-specific fixes:
  source.dirs."prebuilts/misc".postPatch = "ln -sf ${flex}/bin/flex linux-x86/flex/flex-2.5.39";

  kernel.clangVersion = mkDefault "4393122";
}
