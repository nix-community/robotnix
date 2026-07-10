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
  hostPrebuiltTag = if pkgs.stdenv.hostPlatform.isDarwin then "darwin-x86" else "linux-x86";
in
mkIf (config.androidVersion == 9) {
  # Some android version-specific fixes:
  source.dirs."prebuilts/misc".postPatch =
    "ln -sf ${flex}/bin/flex ${hostPrebuiltTag}/flex/flex-2.5.39";

  kernel.clangVersion = mkDefault "4393122";
}
