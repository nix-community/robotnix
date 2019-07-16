{ config, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  tag = {
    marlin = "android-9.0.0_r43";
    taimen = "android-9.0.0_r43";
    crosshatch = "android-9.0.0_r44";
    bonito = "	android-9.0.0_r45";
  }.${config.deviceFamily};
  releases = {
    "android-9.0.0_r43" = {
      rev = "f12a06add10235063c5a856181594b02c5cac769";
      sha256 = "014z7xzn7gbj3bcmmjnzrclnf91ys978d6g849x5dpw0bi0hkzpc";
    };
  };
in
{
  source.manifest = {
    url = mkDefault "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
    rev = mkDefault releases.${tag}.rev;
    sha256 = mkDefault releases.${tag}.sha256;
  };

  kernel.src = builtins.fetchGit {
    url = "https://android.googlesource.com/kernel/msm";
    rev = "a2426c4f8f23a3c14d387d50251de176be4d5b1a"; # as of 2019-7-3, this is android-msm-marlin-3.18-pie-qpr3
    ref = "tags/android-9.0.0_r0.95";
  #    ref = import (runCommand "marlinKernelRev" {} ''
  #        shortrev=$(grep -a 'Linux version' ${config.source.dirs."device/google/marlin-kernel"}/.prebuilt_info/kernel/prebuilt_info_Image_lz4-dtb.asciipb | cut -d " " -f 6 | cut -d '-' -f 2 | sed 's/^g//g')
  #        echo \"$shortrev\" > $out
  #      '');
  };

  removedProductPackages = [ "webview" "Browser2" "Calendar2" "QuickSearchBox" ];

  patches = [ ../../patches/disable-quicksearch.patch ../../patches/fix-device-names.patch ];

  resources."frameworks/base/core/res".config_swipe_up_gesture_setting_available = true; # enable swipe up gesture functionality as option
}
