{ config, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Update. Make an autoupdate script too.
  releases = rec {
    marlin = {
      rev = "android-9.0.0_r43";
      sha256 = "014z7xzn7gbj3bcmmjnzrclnf91ys978d6g849x5dpw0bi0hkzpc";
    };
    taimen = marlin;
    crosshatch = {
      rev = "android-9.0.0_r44";
      sha256 = "0dgxay2q4bq8wxdjvxmf25m90hb1l98aajja9wyp3b06jyn1y0md";
    };
    bonito = {
      rev = "android-9.0.0_r45";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
  };
in
{
  source.manifest = {
    url = mkDefault "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
    rev = mkDefault releases.${config.deviceFamily}.rev;
    sha256 = mkDefault releases.${config.deviceFamily}.sha256;
  };

  # Non-marlin kernels are split up into multiple repos, could be fetched with repo2nix, but it's still messy.
  kernel.src = mkIf (config.deviceFamily == "marlin") (builtins.fetchGit {
    url = "https://android.googlesource.com/kernel/msm";
    rev = "a2426c4f8f23a3c14d387d50251de176be4d5b1a"; # as of 2019-7-3, this is android-msm-marlin-3.18-pie-qpr3
    ref = "tags/android-9.0.0_r0.95";
  });
  #    ref = import (runCommand "marlinKernelRev" {} ''
  #        shortrev=$(grep -a 'Linux version' ${config.source.dirs."device/google/marlin-kernel"}/.prebuilt_info/kernel/prebuilt_info_Image_lz4-dtb.asciipb | cut -d " " -f 6 | cut -d '-' -f 2 | sed 's/^g//g')
  #        echo \"$shortrev\" > $out
  #      '');

  removedProductPackages = [ "webview" "Browser2" "Calendar2" "QuickSearchBox" ];

  patches = [ ../../patches/disable-quicksearch.patch ../../patches/fix-device-names.patch ];

  resources."frameworks/base/core/res".config_swipe_up_gesture_setting_available = true; # enable swipe up gesture functionality as option
}
