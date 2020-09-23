{ config, pkgs, lib, ... }:

with lib;
mkIf (config.androidVersion == 11) {
  warnings = [ "Android 11 support is experimental" ];

  apiLevel = 30;

  source.dirs."build/make" = {
    patches = [
      ./build_make/0001-Readonly-source-fix.patch
    ] ++ (optional (config.flavor != "lineageos")
      (pkgs.substituteAll {
        src = ./build_make/0002-Partition-size-fix.patch;
        inherit (pkgs) coreutils;
      })
    );
  };

  signing.apex.enable = mkDefault true;

  kernel.clangVersion = mkDefault "r370808";

  # Android 11 ninja filters env vars for more correct incrementalism.
  # However, env vars like LD_LIBRARY_PATH must be set for nixpkgs build-userenv-fhs to work
  envVars.ALLOW_NINJA_ENV = "true";

  nixpkgs.overlays = [
    (self: super: {
      android-prepare-vendor = super.android-prepare-vendor.overrideAttrs (attrs: {
        src = pkgs.fetchFromGitHub {
          owner = "AOSPAlliance";
          repo = "android-prepare-vendor";
          rev = "7f19a8ec5b645bfffcf46d5d5ab1eed1d07703ab"; # 2020-09-18
          sha256 = "19axrmvqnj44yzd2198477x4kgazb8cffgmvy4bwwbmby502shwp";
        };
      });
    })
  ];
}
