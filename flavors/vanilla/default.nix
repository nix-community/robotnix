# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers

  phoneDeviceFamilies =
    (optional (config.androidVersion <= 10) "marlin")
    ++ [ "taimen" "muskie" "crosshatch" "bonito" "coral" "sunfish" "redfin" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

  # Replaces references to SystemUIGoogle with SystemUI in device source tree
  patchSystemUIGoogle = ''
    substituteInPlace device.mk --replace SystemUIGoogle SystemUI
    substituteInPlace overlay/frameworks/base/core/res/res/values/config.xml --replace SystemUIGoogle SystemUI
  '';
in mkIf (config.flavor == "vanilla") (mkMerge [

### Generic stuff ###
{
  source.dirs = lib.importJSON (./. + "/repo-${config.source.manifest.rev}.json");
  # Not strictly necessary for me to set this, since I override the source.dirs
  source.manifest.url = mkDefault "https://android.googlesource.com/platform/manifest";

  warnings = optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for vanilla"
    ++ optional (config.androidVersion < 11) "Selected older version of android. Security updates may be out-of-date";

  apv.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
}
{
  ### AOSP usability improvements ###

  # This is the prebuilt webview apk from AOSP. It is very old and not enabled by default.
  # Enable using webview.prebuilt.enable = true;
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

  resources."frameworks/base/core/res".config_swipe_up_gesture_setting_available = true; # enable swipe up gesture functionality as option
  resources."packages/apps/Settings".config_use_legacy_suggestion = false; # fix for cards not disappearing in settings app

  # Don't reboot after flashing image, so the user can relock the bootloader before booting.
  source.dirs."device/common".postPatch = ''
    substituteInPlace generate-factory-images-common.sh --replace "fastboot -w update" "fastboot -w --skip-reboot update"
  '';
}

(mkIf (elem config.androidVersion [ 9 10 11 ]) {
  source.dirs."packages/apps/Launcher3".patches = [ (./. + "/${toString config.androidVersion}/disable-quicksearch.patch") ];
})
(mkIf (elem config.deviceFamily phoneDeviceFamilies) {
  # This might potentially patch multiple files, referring to different
  # devices, all with the name for this device.  This is OK.
  source.dirs."device/google/${config.deviceFamily}".postPatch = ''
    sed -i 's/PRODUCT_MODEL :=.*/PRODUCT_MODEL := ${config.deviceDisplayName}/' aosp_*.mk
    sed -i 's/PRODUCT_MANUFACTURER :=.*/PRODUCT_MANUFACTURER := Google/' aosp_*.mk
  '';
})
(mkIf ((config.deviceFamily == "marlin") && (elem config.androidVersion [ 9 10 ])) {
  # patch location for marlin is different
  source.dirs."device/google/marlin".postPatch = "substituteInPlace common/base.mk --replace SystemUIGoogle SystemUI";
})
(mkIf ((elem config.deviceFamily [ "taimen" "muskie" ]) && (elem config.androidVersion [ 9 10 11 ])) {
  source.dirs."device/google/wahoo".postPatch = patchSystemUIGoogle;
})
(mkIf ((elem config.deviceFamily [ "crosshatch" "bonito" "coral" "sunfish" ])  && (elem config.androidVersion [ 9 10 11 ])) {
  source.dirs."device/google/${config.deviceFamily}".postPatch = patchSystemUIGoogle;
})

### Android 10 stuff ###
(mkIf (config.androidVersion == 10) (mkMerge [

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
  warnings = [ "marlin and sailfish are no longer receiving monthly security updates from Google. Support is left just for testing" ];

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
  kernel.useCustom = mkDefault config.signing.enable;
})

]))


### Android 11 stuff ###
(mkIf (config.androidVersion == 11) (mkMerge [
{
  buildDateTime = mkDefault 1612285669;

  source.manifest.rev = mkDefault "android-11.0.0_r29";
  apv.buildID = mkDefault "RQ1A.210205.004";

  # See also: https://github.com/GrapheneOS/os_issue_tracker/issues/325
  # List of biometric sensors on the device, in decreasing strength. Consumed by AuthService
  # when registering authenticators with BiometricService. Format must be ID:Modality:Strength,
  # where: IDs are unique per device, Modality as defined in BiometricAuthenticator.java,
  # and Strength as defined in Authenticators.java
  resources."frameworks/base/core/res".config_biometric_sensors = {
    value = optional (elem config.deviceFamily [ "taimen" "muskie" "crosshatch" "bonito" ]) "0:2:15"
            ++ optional (config.deviceFamily == "coral") "0:8:15";
    type = "string-array";
  };

  # Clock app needs battery optimization exemption. Currently not in AOSP
  source.dirs."packages/apps/DeskClock".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_packages_apps_DeskClock/commit/0b21e707d7dca4c9c3e4ff030bef8fae3abed088.patch";
      sha256 = "0mzjzxyl8g2i520902bhc3ww3vbcwcx06m3zg033z0w6pw87apqc";
    })
  ];
}
(mkIf (elem config.deviceFamily phoneDeviceFamilies) {
  kernel.useCustom = mkDefault true;
  kernel.configName = mkMerge [
    (mkIf (elem config.deviceFamily [ "taimen" "muskie" ]) "wahoo")
    (mkIf (config.deviceFamily == "crosshatch") "b1c1")
  ];

  # TODO: Could extract the bind-mounting thing in source.nix into something
  # that works for kernels too. Probably not worth the effort for the payoff
  # though.
  kernel.src = let
    kernelName = if elem config.deviceFamily [ "taimen" "muskie"] then "wahoo" else config.deviceFamily;
    kernelMetadata = (lib.importJSON ./kernel-metadata.json).${kernelName};
    kernelRepos = lib.importJSON (./. + "/repo-${kernelMetadata.branch}.json");
    kernelDirs = {
      "" = "private/msm-google";
    } // optionalAttrs (elem kernelName [ "crosshatch" "bonito" "coral" "sunfish" "redfin" ]) {
      "techpack/audio" = "private/msm-google/techpack/audio";
      "drivers/staging/qca-wifi-host-cmn" = "private/msm-google-modules/wlan/qca-wifi-host-cmn";
      "drivers/staging/qcacld-3.0" = "private/msm-google-modules/wlan/qcacld-3.0";
      "drivers/staging/fw-api" = "private/msm-google-modules/wlan/fw-api";
    } // optionalAttrs (elem kernelName [ "coral" "sunfish" "redfin" ]) {
      "drivers/input/touchscreen/fts_touch" = "private/msm-google-modules/touch/fts";
      # TODO: What is the fts_touch_s5 repo for sunfish?
    } // optionalAttrs (elem kernelName [ "redfin" ]) {
      "techpack/dataipa" = "private/msm-google/techpack/dataipa";
      "techpack/display" = "private/msm-google/techpack/display";
      "techpack/video" = "private/msm-google/techpack/video";
      "techpack/audio" = "private/msm-google/techpack/audio";
      "drivers/input/touchscreen/sec_touch" = "private/msm-google-modules/touch/sec";
      "arch/arm64/boot/dts/vendor" = "private/msm-google/arch/arm64/boot/dts/vendor";
      "arch/arm64/boot/dts/vendor/qcom/camera" = "private/msm-google/arch/arm64/boot/dts/vendor/qcom/camera";
      "arch/arm64/boot/dts/vendor/qcom/display" = "private/msm-google/arch/arm64/boot/dts/vendor/qcom/display";
    };
    fetchedRepo = repo: pkgs.fetchgit {
      inherit (kernelRepos.${repo}) url rev sha256;
    };
  in pkgs.runCommand "kernel-src" {}
    (concatStringsSep "\n" (lib.mapAttrsToList (relpath: repo: ''
      ${lib.optionalString (relpath != "") "mkdir -p $out/$(dirname ${relpath})"}
      cp -r ${fetchedRepo repo} $out/${relpath}
      chmod u+w -R $out/${relpath}
    '') kernelDirs));

  kernel.buildProductFilenames = [ "**/*.ko" ]; # Copy kernel modules if they exist
})
(mkIf (elem config.device [ "taimen" "walleye" ]) {
  warnings = [ "taimen and walleye are no longer receiving monthly vendor security updates from Google. Support is left just for testing" ];
  source.manifest.rev = "android-11.0.0_r25"; # More recent sources don't even include device/google/muskie
  apv.buildID = "RP1A.201005.004.A1";
})

]))

(mkIf (config.androidVersion == 12) {
  source.manifest.rev = mkDefault "android-s-preview-1";
  buildDateTime = mkDefault 1613683757;

  # Build fails otherwise complaining about soong visibility for some art module
  source.dirs.libcore.src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/libcore";
    rev = "dc5351ff0193f6c82478981e32561a779651821a";
    sha256 = "1hs9rmssfg4qjsbfd26psj4n3ayd5q5bfpswc2jcly3pym1gdnn5";
  };
})

])
