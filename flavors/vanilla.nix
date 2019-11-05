{ config, pkgs, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Make an autoupdate script too.
  release = rec {
    marlin = { # TODO: Marlin is no longer updated
      tag = "android-10.0.0_r5"; # QP1A.191005.007.A1
      sha256 = "10gw8xxk62fnlj1y2lsr23wrzh59kxchqg8f7hzmzbw0qvlrvsqg";
    };
    taimen = {
      tag = "android-10.0.0_r11"; # QP1A.191105.004
      sha256 = "02cxv983wl6kqm7jbij1wswvp5wi96wivr1fj46kv09sqr9zr7sr";
    };
    crosshatch = taimen;
    bonito = taimen;
    coral = {
      tag = "android-10.0.0_r14"; # QP1A.190821.014.C2
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
  }.${config.deviceFamily};
  kernelTag = {
    taimen = "android-10.0.0_r0.18";
    crosshatch = "android-10.0.0_r0.19";
    bonito = "android-10.0.0_r0.20";
    coral = "android-10.0.0_r0.21";
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
  kernel.src = builtins.fetchGit {
    url = "https://android.googlesource.com/kernel/msm";
    ref = "refs/tags/${kernelTag}";
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
}
