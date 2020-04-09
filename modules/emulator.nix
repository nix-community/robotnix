{ config, pkgs, lib, ... }:

with lib;
{
  config.build = {
    # TODO: Maybe include these in the standard build.android drv?
    sysimg = config.build.mkAndroid {
      name = "robotnix-sysimg";
      makeTargets = [ "droid" ];
      installPhase = ''
        mkdir -p $out
        cp --reflink=auto $ANDROID_PRODUCT_OUT/vendor-qemu.img $out/vendor.img
        cp --reflink=auto $ANDROID_PRODUCT_OUT/system-qemu.img $out/system.img
        cp --reflink=auto $ANDROID_PRODUCT_OUT/ramdisk.img $out/ramdisk.img
        cp --reflink=auto $ANDROID_PRODUCT_OUT/userdata.img $out/userdata.img
        cp --reflink=auto -r $ANDROID_PRODUCT_OUT/data $out/
        cp --reflink=auto $ANDROID_PRODUCT_OUT/system/build.prop $out/build.prop
        cp --reflink=auto $ANDROID_PRODUCT_OUT/VerifiedBootParams.textproto $out/

        # sdk-android-x86.atree
        cp --reflink=auto $ANDROID_PRODUCT_OUT/kernel-ranchu-64 $out/kernel-ranchu-64
        cp --reflink=auto $ANDROID_PRODUCT_OUT/encryptionkey.img $out/encryptionkey.img
        cp --reflink=auto $ANDROID_PRODUCT_OUT/advancedFeatures.ini $out/advancedFeatures.ini
      '';
    };

    emulator = pkgs.android-emulator.bindImg config.build.sysimg;
  };
}
