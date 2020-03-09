{ config, pkgs, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Make an autoupdate script too.
  kernelSrc = { rev, sha256 }: pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/msm";
    inherit rev sha256;
  };
  supportedDeviceFamilies = [ "marlin" "taimen" "crosshatch" "bonito" "coral" ];
  deviceDirName = if (config.device == "walleye") then "muskie" else config.deviceFamily;
in mkIf (config.flavor == "vanilla") (mkMerge [
{
  source.manifest.url = "https://android.googlesource.com/platform/manifest";
}
(mkIf (config.deviceFamily == "marlin") {
  source.buildNumber = "QP1A.191005.007.A3";
  source.manifest.rev = "android-10.0.0_r17";
  source.manifest.sha256 = "12i292cb97aqs9dl1bkkm1mnq7immxxnrbighxj4xrywgp46mh9l";
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.23";
    sha256 = "0wy6h97g9j5sma67brn9vxq7jzf169j2gzq4ai96v4h68lz39lq9";
  };
  # TODO: Only build kernel for marlin since it needs verity key in build.
  # Kernel sources for crosshatch and bonito require multiple repos--which
  # could normally be fetched with repo at https://android.googlesource.com/kernel/manifest
  # but google didn't push a branch like android-msm-crosshatch-4.9-pie-qpr3 to that repo.
  kernel.useCustom = mkDefault config.signBuild;
})
(mkIf ((elem config.deviceFamily [ "taimen" "bonito" "crosshatch" ]) || (config.device == "x86")) {
  source.buildNumber = "QQ1A.200305.002";
  source.manifest.rev = "android-10.0.0_r30";
  source.manifest.sha256 = "1kvbzcxbn78kvjnd96mjy59yfqyaqkyd28kay24k85lb04991qxx";

  # TODO: temporary fix for missing apifinder until upstream issue is resolved: https://issuetracker.google.com/issues/150626837
  source.dirs."tools/apifinder".contents = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/tools/apifinder";
    rev = "refs/tags/android-mainline-10.0.0_r9";
    sha256 =  "0hcbvs6dns11b83877wy5g3pzyq8f7f71mcas6npi5y8ka503kv9";
  };
})
(mkIf (config.deviceFamily == "taimen") {
  kernel.src = kernelSrc {
    tag = "android-10.0.0_r0.32";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "crosshatch") {
  kernel.src = kernelSrc {
    tag = "android-10.0.0_r0.26";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "bonito") {
  kernel.src = kernelSrc {
    tag = "android-10.0.0_r0.28";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "coral") {
  source.buildNumber = "QQ1B.200305.002";
  source.manifest.rev = "android-10.0.0_r31";
  source.manifest.sha256 = "1bwl12dj7x0a1nxxkm9k6a5ixgcmiw724fdbw8ny2ycm4divv763";
  kernel.src = kernelSrc {
    tag = "android-10.0.0_r0.35";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.buildProduct == "sdk") {
  source.manifest.rev = "platform-tools-29.0.5"; # TODO: 29.0.6 is out now
  source.manifest.sha256 = "0v9zaplr993wa8fgd0g7mik3qrcbq6y1ywpmq1jdwzdz2yawjacp";
})

# AOSP usability improvements for device builds
(mkIf (elem config.deviceFamily supportedDeviceFamilies) {
  webview.prebuilt.apk = config.source.dirs."external/chromium-webview".contents + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;

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
})
])
