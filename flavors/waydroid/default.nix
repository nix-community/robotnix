# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkIf
    mkMerge
    mkBefore
    ;
  repoDirs = lib.importJSON ./repo-lineage-17.1.json;
  patchMetadata = lib.importJSON ./patch-metadata.json;
  repoDateTimes = lib.mapAttrsToList (name: value: value.dateTime) repoDirs;
  maxRepoDateTime = lib.foldl (a: b: lib.max a b) 0 repoDateTimes;
in
mkIf (config.flavor == "waydroid") {
  buildDateTime = mkDefault maxRepoDateTime;

  androidVersion = mkDefault 10;
  productNamePrefix = "lineage_waydroid_";
  variant = mkDefault "userdebug";

  source.dirs = mkMerge [
    repoDirs
    (lib.mapAttrs (relpath: patches: {
      gitPatches = (
        builtins.map (p: "${config.source.dirs."vendor/extra".src}/${patches.dir}/${p}") patches.files
      );
    }) patchMetadata)
  ];

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL"; # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # Traceback (most recent call last):
  #   File "external/mesa3d/src/panfrost/bifrost/bi_printer.c.py", line 203, in <module>
  #     from mako.template import Template
  # ModuleNotFoundError: No module named 'mako'
  # TODO: mkBefore here is a hack
  envPackages =
    with pkgs;
    mkBefore [
      (python2.withPackages (p: with p; [ Mako ]))
      (python3.withPackages (p: with p; [ Mako ]))
    ];

  build = {
    waydroid = config.build.mkAndroid {
      name = "robotnix-${config.productName}-${config.buildNumber}";
      makeTargets = [
        "systemimage"
        "vendorimage"
      ];
      installPhase = ''
        mkdir -p $out

        cp -t $out \
          $ANDROID_PRODUCT_OUT/android-info.txt      \
          $ANDROID_PRODUCT_OUT/build_fingerprint.txt \
          $ANDROID_PRODUCT_OUT/installed-files.txt

        for v in system.img vendor.img; do
          ${pkgs.simg2img}/bin/simg2img $ANDROID_PRODUCT_OUT/$v $out/$v
          ${pkgs.e2fsprogs}/bin/e2fsck -fy $out/$v
          ${pkgs.e2fsprogs}/bin/resize2fs -M $out/$v
        done
      '';
    };
  };
}
