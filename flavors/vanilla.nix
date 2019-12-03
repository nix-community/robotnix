{ config, pkgs, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Make an autoupdate script too.
  release = rec {
    marlin = {
      tag = "android-10.0.0_r17"; # QP1A.191005.007.A3
      sha256 = "1ay3dynd9abvd021ghafx5winzj4rfqr8wzq83cvgwxm1dmfis5j";
    };
    taimen = {
      tag = "android-10.0.0_r15"; # QQ1A.191205.008
      sha256 = "1a7cf8pjsz0fpksy3gi28dswv9zigg89bhqrxgvm0ddmhfxygan3";
    };
    crosshatch = taimen;
    bonito = {
      tag = "android-10.0.0_r16"; # QQ1A.191205.011
      sha256 = "0nz4lhxas4hhlhfih2rnv9acwir0k4z6mx53js948hqb1bbprk5z";
    };
    coral = {
      tag = "android-10.0.0_r14"; # QP1A.190821.014.C2
      sha256 = "0gmas0jdarz8yqvd4chg5sxkqssw74bgg37xl8bdjvc8a7c58003";
    };
  }.${config.deviceFamily};
  kernelRelease = {
    marlin = {
      tag = "android-10.0.0_r0.23";
      sha256 = "0wy6h97g9j5sma67brn9vxq7jzf169j2gzq4ai96v4h68lz39lq9";
    };
    taimen = {
      tag = "android-10.0.0_r0.24";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
    crosshatch = {
      tag = "android-10.0.0_r0.26"; # TODO: Get the other sources for these kernels
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
    bonito = {
      tag = "android-10.0.0_r0.28";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
    coral = {
      tag = "android-10.0.0_r0.21";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
  }.${config.deviceFamily};
  deviceDirName = if (config.device == "walleye") then "muskie" else config.deviceFamily;
in
mkIf (config.flavor == "vanilla") {
  source.manifest = {
    url = mkDefault "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
    rev = mkDefault "refs/tags/${release.tag}";
    sha256 = mkDefault release.sha256;
  };

  # TODO: Only build kernel for marlin since it needs verity key in build.
  # Kernel sources for crosshatch and bonito require multiple repos--which
  # could normally be fetched with repo at https://android.googlesource.com/kernel/manifest
  # but google didn't push a branch like android-msm-crosshatch-4.9-pie-qpr3 to that repo.
  kernel.useCustom = mkDefault (config.signBuild && (config.deviceFamily == "marlin"));
  kernel.src = pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/msm";
    rev = kernelRelease.tag;
    sha256 = kernelRelease.sha256;
  };

  removedProductPackages = [ "webview" "Browser2" "QuickSearchBox" ];
  source.dirs."external/chromium-webview".enable = false;
  source.dirs."packages/apps/QuickSearchBox".enable = false;
  source.dirs."packages/apps/Browser2".enable = false;

  source.dirs."packages/apps/Launcher3".patches = [ (../patches + "/${toString config.androidVersion}" + /disable-quicksearch.patch) ];
  source.dirs."device/google/${deviceDirName}".patches = [
    (../patches + "/${toString config.androidVersion}/${deviceDirName}-fix-device-names.patch")
  ];

  source.dirs."packages/apps/DeskClock".patches = mkIf (config.androidVersion == 10) [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_packages_apps_DeskClock/commit/f31333513b1bf27ae23c61e4ba938568cc9e7b76.patch";
      sha256 = "1as8vyhfyi9cj61fc80ajskyz4lwwdc85fgxhj0b69z0dbxm77pj";
    })
  ];

  resources."frameworks/base/core/res".config_swipe_up_gesture_setting_available = true; # enable swipe up gesture functionality as option
  resources."packages/apps/Settings".config_use_legacy_suggestion = false; # fix for cards not disappearing in settings app
}
