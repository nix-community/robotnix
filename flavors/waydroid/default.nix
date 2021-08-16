# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    mkDefault
    mkIf
    mkMerge
    mkBefore
  ;
  repoDirs = lib.importJSON (./. + "/repo-lineage-17.1.json");
  patchMetadata = lib.importJSON ./patch-metadata.json;
in mkIf (config.flavor == "waydroid")
{
  buildDateTime = mkDefault 1629060864;

  androidVersion = mkDefault 10;
  productNamePrefix = "lineage_anbox_";
  variant = mkDefault "userdebug";

  source.dirs = mkMerge [
    repoDirs
    (lib.mapAttrs (relpath: patches: {
      patches = (builtins.map (p: "${config.source.dirs."anbox-patches".src}/${relpath}/${p}") patches);
    }) patchMetadata)
  ];

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL";  # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # Traceback (most recent call last):
  #   File "external/mesa3d/src/panfrost/bifrost/bi_printer.c.py", line 203, in <module>
  #     from mako.template import Template
  # ModuleNotFoundError: No module named 'mako'
  # TODO: mkBefore here is a hack
  envPackages = with pkgs; mkBefore [
    (python2.withPackages (p: with p; [ Mako ]))
    (python3.withPackages (p: with p; [ Mako ]))
  ];

  build = {
    waydroid = config.build.mkAndroid {
      name = "robotnix-${config.productName}-${config.buildNumber}";
      makeTargets = [ "systemimage" "vendorimage" ];
      installPhase = ''
        mkdir -p $out

        cp -t $out \
          $ANDROID_PRODUCT_OUT/android-info.txt      \
          $ANDROID_PRODUCT_OUT/build_fingerprint.txt \
          $ANDROID_PRODUCT_OUT/installed-files.txt

        cp --reflink=auto -r $ANDROID_PRODUCT_OUT/system.img $out
        cp --reflink=auto -r $ANDROID_PRODUCT_OUT/vendor.img $out
      '';
    };
  };
}
