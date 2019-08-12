{ config, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Update. Make an autoupdate script too.
  release = rec {
    marlin = {
      tag = "android-9.0.0_r46"; # PQ3A.190801.002
      sha256 = "08hjjmyrr4isb1hl3wixyysp9792bh2pp0ifh9w9p5v90nx7s1sz";
    };
    taimen = marlin;
    crosshatch = marlin;
    bonito = {
      tag = "android-9.0.0_r47"; # PQ3B.190801.002
      sha256 = "0wqcy2708i8znr3xqkmafrk5dvf9z222f3705j3l2jdb67aqim49";
    };
  }.${config.deviceFamily};
in
{
  imports = [ ./exclude.nix ];

  source.manifest = {
    url = mkDefault "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
    rev = mkDefault "refs/tags/${release.tag}";
    sha256 = mkDefault release.sha256;
  };

  # TODO: Only build kernel for marlin since it needs verity key in build. In future, extend this to all devices.
  kernel.src = mkIf (config.deviceFamily == "marlin") (builtins.fetchGit {
    url = "https://android.googlesource.com/kernel/msm";
    #rev = "a2426c4f8f23a3c14d387d50251de176be4d5b1a"; # as of 2019-7-3, this is android-msm-marlin-3.18-pie-qpr3
    #ref = "tags/android-9.0.0_r0.95";
    ref = "android-msm-marlin-3.18-pie-qpr3";
  });

  removedProductPackages = [ "webview" "Browser2" "Calendar" "QuickSearchBox" ];
  source.dirs."external/chromium-webview".enable = false;
  source.dirs."packages/apps/Calendar".enable = false;
  source.dirs."packages/apps/QuickSearchBox".enable = false;
  source.dirs."packages/apps/Browser2".enable = false;

  source.patches = [ ../../patches/disable-quicksearch.patch ../../patches/fix-device-names.patch ];

  resources."frameworks/base/core/res".config_swipe_up_gesture_setting_available = true; # enable swipe up gesture functionality as option
}
