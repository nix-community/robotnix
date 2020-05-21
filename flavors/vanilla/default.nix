{ config, pkgs, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Make an autoupdate script too.
  kernelSrc = { rev, sha256 }: pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/msm";
    inherit rev sha256;
  };

  supportedDeviceFamilies = [ "marlin" "taimen" "muskie" "crosshatch" "bonito" "coral" "generic"];

in mkIf (config.flavor == "vanilla") (mkMerge [
{
  source.dirs = lib.importJSON (./. + "/${config.source.manifest.rev}.json");
  # Not strictly necessary for me to set this, since I override the jsonFile
  source.manifest.url = mkDefault "https://android.googlesource.com/platform/manifest";

  warnings = optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for vanilla";
}
{
  ### AOSP usability improvements ###

  # This is the prebuilt webview apk from AOSP. It is very old and not enabled by default.
  # Enable using webview.prebuild.enable = true;
  webview.prebuilt.apk = config.source.dirs."external/chromium-webview".src + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;

  # Instead, we build our own chromium and webview
  apps.chromium.enable = mkDefault true;
  webview.chromium.availableByDefault = mkDefault true;
  webview.chromium.enable = mkDefault true;

  removedProductPackages = [ "webview" "Browser2" "QuickSearchBox" ];
  source.dirs."external/chromium-webview".enable = false;
  source.dirs."packages/apps/QuickSearchBox".enable = false;
  source.dirs."packages/apps/Browser2".enable = false;

  source.dirs."packages/apps/Launcher3".patches = [ (./. + "/${toString config.androidVersion}/disable-quicksearch.patch") ];
  source.dirs."device/google/marlin".patches = [ (./. + "/${toString config.androidVersion}/marlin-fix-device-names.patch") ];
  source.dirs."device/google/taimen".patches = [ (./. + "/${toString config.androidVersion}/taimen-fix-device-names.patch") ];
  source.dirs."device/google/muskie".patches = [ (./. + "/${toString config.androidVersion}/muskie-fix-device-names.patch") ];
  source.dirs."device/google/crosshatch".patches = [ (./. + "/${toString config.androidVersion}/crosshatch-fix-device-names.patch") ];
  source.dirs."device/google/bonito".patches = [ (./. + "/${toString config.androidVersion}/bonito-fix-device-names.patch") ];

  source.dirs."packages/apps/DeskClock".patches = mkIf (config.androidVersion == 10) [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_packages_apps_DeskClock/commit/f31333513b1bf27ae23c61e4ba938568cc9e7b76.patch";
      sha256 = "1as8vyhfyi9cj61fc80ajskyz4lwwdc85fgxhj0b69z0dbxm77pj";
    })
  ];

  resources."frameworks/base/core/res".config_swipe_up_gesture_setting_available = true; # enable swipe up gesture functionality as option
  resources."packages/apps/Settings".config_use_legacy_suggestion = false; # fix for cards not disappearing in settings app
}
(mkIf (elem config.deviceFamily supportedDeviceFamilies) {
  buildNumber = mkDefault "2020.05.04.17";
  buildDateTime = mkDefault 1588626224;
})
(mkIf ((elem config.deviceFamily [ "taimen" "muskie" ])) {
  vendor.buildID = mkDefault "QQ2A.200501.001.B3";
  source.manifest.rev = mkDefault "android-10.0.0_r36";
})
(mkIf ((elem config.deviceFamily [ "bonito" "crosshatch" "coral" "generic"])) {
  vendor.buildID = mkDefault "QQ2A.200501.001.B2";
  source.manifest.rev = mkDefault "android-10.0.0_r35";
})
# TODO: Build kernels for non marlin/sailfish devices
(mkIf (config.deviceFamily == "taimen" || config.deviceFamily == "muskie") {
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.32";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "crosshatch") {
  kernel.configName = "b1c1";
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.26";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "bonito") {
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.28";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "coral") {
  kernel.src = kernelSrc {
    tag = "android-10.0.0_r0.35";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "marlin") {
  warnings = [ "marlin and sailfish are no longer receiving monthly security updates from Google. Support is left just for testing" ];

  vendor.buildID = mkDefault "QP1A.191005.007.A3";
  source.manifest.rev = mkDefault "android-10.0.0_r35";

  # HACK to use recent android source, but with old vendor files...
  source.dirs."vendor/google_devices".postPatch = ''
    echo QQ2A.200501.001.B2 > ${config.device}/build_id.txt
  '';

  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.23";
    sha256 = "0wy6h97g9j5sma67brn9vxq7jzf169j2gzq4ai96v4h68lz39lq9";
  };

  # Fix reproducibility issue with DTBs not being sorted
  kernel.postPatch = ''
    sed -i \
      's/^DTB_OBJS := $(shell find \(.*\))$/DTB_OBJS := $(sort $(shell find \1))/' \
      arch/arm64/boot/Makefile
  '';

  # TODO: Only build kernel for marlin since it needs verity key in build.
  # Kernel sources for crosshatch and bonito require multiple repos--which
  # could normally be fetched with repo at https://android.googlesource.com/kernel/manifest
  # but google didn't push a branch like android-msm-crosshatch-4.9-pie-qpr3 to that repo.
  kernel.useCustom = mkDefault config.signBuild;
})
])
