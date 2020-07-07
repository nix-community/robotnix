{ config, pkgs, lib, ... }:

with lib;
mkIf (config.androidVersion == 11) {
  warnings = [ "Android 11 support is experimental" ];

  source.dirs."build/make" = {
    patches = [
      ./build_make/0001-Readonly-source-fix.patch
      (pkgs.substituteAll {
        src = ./build_make/0002-Partition-size-fix.patch;
        inherit (pkgs) coreutils;
      })
    ];
  };

  apex.enable = mkDefault true;

  #kernel.clangVersion = mkDefault "r349610";
}
