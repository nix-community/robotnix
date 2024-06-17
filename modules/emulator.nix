# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

{
  config.build = {
    # TODO: Maybe include these in the standard build.android drv?
    # TODO: Compare this with "nix-build ./default.nix -A packages.canary.system-images.android-29.default.x86
    sysimg = config.build.mkAndroid {
      name = "robotnix-sysimg";
      makeTargets = [ "droid" ];
      installPhase = ''
        mkdir -p $out
        cp --reflink=auto $ANDROID_PRODUCT_OUT/vendor-qemu.img $out/vendor.img || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/system-qemu.img $out/system.img || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/ramdisk${
          lib.optionalString (config.androidVersion >= 11) "-qemu"
        }.img $out/ramdisk.img || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/userdata.img $out/userdata.img || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/vbmeta.img $out/vbmeta.img || true
        cp --reflink=auto -r $ANDROID_PRODUCT_OUT/data $out/ || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/system/build.prop $out/build.prop || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/VerifiedBootParams.textproto $out/ || true

        # sdk-android-x86.atree
        cp --reflink=auto $ANDROID_PRODUCT_OUT/kernel-ranchu* $out/ || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/encryptionkey.img $out/encryptionkey.img || true
        cp --reflink=auto $ANDROID_PRODUCT_OUT/advancedFeatures.ini $out/advancedFeatures.ini || true
      '';
    };

    emulator = pkgs.android-emulator.bindImg {
      img = config.build.sysimg;
      avd = {
        abi.type = config.arch; # TODO: Add all ABIs it supports
        hw.cpu.arch = config.arch;
      };
    };
  };
}
