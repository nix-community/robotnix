# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault;

  inherit (import ./supported-devices.nix { inherit lib config; })
    supportedDeviceFamilies phoneDeviceFamilies;

  # Replaces references to SystemUIGoogle with SystemUI in device source tree
  patchSystemUIGoogle = ''
    substituteInPlace device.mk --replace SystemUIGoogle SystemUI
    substituteInPlace overlay/frameworks/base/core/res/res/values/config.xml --replace SystemUIGoogle SystemUI
  '';
in mkIf (config.flavor == "vanilla") (mkMerge [

### Generic stuff ###
{
  source.dirs = lib.importJSON (./. + "/${builtins.toString config.androidVersion}/repo-${config.source.manifest.rev}.json");
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

(mkIf (elem config.androidVersion [ 9 10 11 12 ]) {
  source.dirs."packages/apps/Launcher3".patches = [ (./. + "/${toString config.androidVersion}/disable-quicksearch.patch") ];
})
(mkIf (elem config.deviceFamily phoneDeviceFamilies) {
  # This might potentially patch multiple files, referring to different
  # devices, all with the name for this device.  This is OK.
  source.dirs."device/google/${config.deviceFamily}".postPatch = ''
    sed -i 's/PRODUCT_MODEL :=.*/PRODUCT_MODEL := ${config.deviceDisplayName}/' aosp_*.mk
    sed -i 's/PRODUCT_BRAND :=.*/PRODUCT_BRAND := google/' aosp_*.mk
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
(mkIf ((elem config.deviceFamily [ "crosshatch" "bonito" "coral" "sunfish" "redfin" "raviole" ]) && (elem config.androidVersion [ 9 10 11 12 ])) (let
  dirName =
    if config.deviceFamily == "redfin" then "redbull"
    else if config.deviceFamily == "raviole" then "gs101"
    else config.deviceFamily;
in {
  source.dirs."device/google/${dirName}".postPatch = patchSystemUIGoogle;
}))

])
