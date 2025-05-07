# SPDX-FileCopyrightText: 2021 Samuel Dionne-Riel
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    mkDefault
    mkIf
    mkMerge
  ;
  androidVersionToTWRPBranch = {
    "9" = "twrp-9.0";
    "10" = "twrp-10.0-deprecated";
  };
  TWRPBranch = androidVersionToTWRPBranch.${toString config.androidVersion};
  repoDirs = lib.importJSON (./. + "/${TWRPBranch}/repo.json");
in mkIf (config.flavor == "twrp")
(mkMerge [
{
  # Defaults elsewhere makes it default to `12` if unset.
  androidVersion = mkDefault (builtins.throw "androidVersion needs to be set according to your device tree.");

  # product names start with "omni_"
  #  → lunch omni_sailfish-eng
  productNamePrefix = "omni_";

  buildDateTime = mkDefault 1616627550;

  # TWRP uses this by default. If your device supports it, I recommend using variant = "user"
  variant = mkDefault "eng";

  source.dirs = mkMerge ([
    repoDirs
  ]);

  source.manifest.url = mkDefault "https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git";
  source.manifest.rev = mkDefault "refs/heads/${TWRPBranch}";
  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL";  # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  build = {
    twrp = config.build.mkAndroid {
      name = "robotnix-${config.productName}-${config.buildNumber}";
      makeTargets = [ "recoveryimage" ];
      # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
      installPhase = ''
        mkdir -p $out
        cp --reflink=auto $ANDROID_PRODUCT_OUT/recovery.img $out/
      '';
    };
  };
}
(mkIf (config.androidVersion == 9) {
  source.dirs = mkMerge ([
    repoDirs
    {
      "bootable/recovery" = {
        patches = [
          ./patches/android_bootable_recovery/0001-gui-Don-t-preserve-mode-owner-when-copying-files.patch
        ];
      };
      "build/make" = {
        patches = [
          ./patches/android_build/0001-Work-around-source-files-being-read-only.patch
        ];
      };
    }
  ]);
})
(mkIf (config.androidVersion == 10) {
  # It seems to want a lot of packages normally present in androidVersion == 9...
  envPackages = with pkgs; [
      openssl.dev
      bison
      flex
      perl
      which
  ];

  # Ugh, something really wants `ccache` in these repos.
  # :/
  ccache.enable = lib.mkForce true;
  envVars = {
    CCACHE_DIR = lib.mkForce "/tmp"; # Make configurable?
  };
})
])
