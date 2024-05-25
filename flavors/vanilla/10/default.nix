{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    elem
    mkIf
    mkMerge
    mkDefault
    ;

  inherit (import ../supported-devices.nix { inherit lib config; })
    supportedDeviceFamilies
    phoneDeviceFamilies
    ;
in
(mkIf (config.flavor == "vanilla" && config.androidVersion == 10) (mkMerge [

  (mkIf ((elem config.deviceFamily supportedDeviceFamilies) && (config.device != "sunfish")) {
    buildDateTime = mkDefault 1596503967;
    apv.buildID = mkDefault "QQ3A.200805.001";
    source.manifest.rev = mkDefault "android-10.0.0_r41";
  })
  (mkIf (config.device == "sunfish") {
    buildDateTime = mkDefault 1598591122;
    apv.buildID = mkDefault "QD4A.200805.003";
    source.manifest.rev = mkDefault "android-10.0.0_r45";
  })
  {
    source.dirs."packages/apps/DeskClock".patches = [
      (pkgs.fetchpatch {
        url = "https://github.com/GrapheneOS/platform_packages_apps_DeskClock/commit/f31333513b1bf27ae23c61e4ba938568cc9e7b76.patch";
        sha256 = "1as8vyhfyi9cj61fc80ajskyz4lwwdc85fgxhj0b69z0dbxm77pj";
      })
    ];
  }
  (mkIf (config.deviceFamily == "marlin") {
    warnings = [
      "marlin and sailfish are no longer receiving monthly security updates from Google. Support is left just for testing"
    ];

    apv.buildID = "QP1A.191005.007.A3";
    source.manifest.rev = "android-10.0.0_r41";

    # HACK to use recent android source, but with old vendor files...
    source.dirs."vendor/google_devices".postPatch = ''
      echo QQ3A.200805.001 > ${config.device}/build_id.txt
    '';

    kernel.src = pkgs.fetchgit {
      url = "https://android.googlesource.com/kernel/msm";
      rev = "android-10.0.0_r0.23";
      sha256 = "0wy6h97g9j5sma67brn9vxq7jzf169j2gzq4ai96v4h68lz39lq9";
    };

    # Fix reproducibility issue with DTBs not being sorted
    kernel.postPatch = ''
      sed -i \
        's/^DTB_OBJS := $(shell find \(.*\))$/DTB_OBJS := $(sort $(shell find \1))/' \
        arch/arm64/boot/Makefile
    '';

    # TODO: Currently, only build kernel for marlin since it needs verity key in build.
    # Could also build for other devices, like is done for Android 11
    kernel.enable = mkDefault config.signing.enable;
  })

]))
