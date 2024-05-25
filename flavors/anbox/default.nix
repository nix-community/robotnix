# SPDX-FileCopyrightText: 2021 Samuel Dionne-Riel
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkDefault mkIf mkMerge;
  anboxBranch = "pmanbox";
  repoDirs = lib.importJSON (./. + "/repo-${anboxBranch}.json");
in
mkIf (config.flavor == "anbox") {
  androidVersion = mkDefault 7;

  # product names start with "anbox_"
  #  → lunch anbox_arm64-user
  productNamePrefix = "anbox_";

  buildDateTime = mkDefault 1623041218;

  variant = mkDefault "user";

  source.dirs = mkMerge ([
    repoDirs
    { "build".patches = [ ./webview-hack.patch ]; }
  ]);

  source.manifest.url = mkDefault "https://github.com/pmanbox/platform_manifests.git";
  source.manifest.rev = mkDefault "refs/heads/${anboxBranch}";
  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL"; # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  build = {
    anbox = config.build.mkAndroid {
      name = "robotnix-${config.productName}-${config.buildNumber}";
      makeTargets = [
        # default
      ];
      # How postmarketOS packages theirs:
      # https://gitlab.com/postmarketOS/anbox-image-make/
      # Which in turn calls `create-package.sh`
      # https://github.com/anbox/anbox/blob/ad377ff25354d68b76e2b8da24a404850f8514c6/scripts/create-package.sh
      # But really we're skipping all of this and building the image ourselves.
      # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
      installPhase = ''
        mkdir -p $out

        # Misc files
        cp -t $out \
          $ANDROID_PRODUCT_OUT/android-info.txt      \
          $ANDROID_PRODUCT_OUT/build_fingerprint.txt \
          $ANDROID_PRODUCT_OUT/installed-files.txt

        # Building the rootfs
        cp --reflink=auto -r $ANDROID_PRODUCT_OUT/root anbox-root
        rmdir anbox-root/system
        cp --reflink=auto -r $ANDROID_PRODUCT_OUT/system anbox-root/system

        # Producing the squashfs img
        ${pkgs.squashfsTools}/bin/mksquashfs \
          anbox-root \
          $out/anbox.img \
          -comp xz -no-xattrs -all-root
      '';
    };
  };
}
