
{ config, pkgs, lib, ... }:

with lib;
let
  flex = pkgs.callPackage ./flex-2.5.39.nix {};
in
mkIf (config.androidVersion == 9) {
  # Some android version-specific fixes:
  source.dirs."prebuilts/misc".postPatch = "ln -sf ${flex}/bin/flex linux-x86/flex/flex-2.5.39";

  kernel.clangVersion = mkDefault "4393122";
}
