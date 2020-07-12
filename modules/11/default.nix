{ config, pkgs, lib, ... }:

with lib;
mkIf (config.androidVersion == 11) {
  warnings = [ "Android 11 support is experimental" ];

  apiLevel = 30;

  source.dirs."build/make" = {
    patches = [
      ./build_make/0001-Readonly-source-fix.patch
    ];
  };

  apex.enable = mkDefault true;

  #kernel.clangVersion = mkDefault "r349610";
}
