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

  # Android 11 ninja filters env vars for more correct incrementalism.
  # However, env vars like LD_LIBRARY_PATH must be set for nixpkgs build-userenv-fhs to work
  envVars.ALLOW_NINJA_ENV = "true";
}
