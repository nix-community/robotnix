{ config, pkgs, lib, ... }:
with lib;
let
  # https://source.android.com/setup/start/build-numbers
  # TODO: Make an autoupdate script too.
  kernelSrc = { rev, sha256 }: pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/msm";
    inherit rev sha256;
  };

  phoneDeviceFamilies =
    (optional (config.androidVersion <= 10) "marlin")
    ++ [ "taimen" "muskie" "crosshatch" "bonito" "coral" "sunfish" ];
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
  # Not strictly necessary for me to set this, since I override the jsonFile
  source.manifest.url = mkDefault "https://android.googlesource.com/platform/manifest";

  warnings = optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for vanilla";

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
}

(mkIf (elem config.androidVersion [ 9 10 ]) {
  source.dirs."device/google/marlin".patches = [ (./. + "/${toString config.androidVersion}/marlin-fix-device-names.patch") ];
  # patch location for marlin is different
  source.dirs."device/google/marlin".postPatch = "substituteInPlace common/base.mk --replace SystemUIGoogle SystemUI";
})
(mkIf (elem config.androidVersion [ 9 10 11 ]) {
  source.dirs."packages/apps/Launcher3".patches = [ (./. + "/${toString config.androidVersion}/disable-quicksearch.patch") ];
  source.dirs."device/google/taimen".patches = [ (./. + "/${toString config.androidVersion}/taimen-fix-device-names.patch") ];
  source.dirs."device/google/muskie".patches = [ (./. + "/${toString config.androidVersion}/muskie-fix-device-names.patch") ];
  source.dirs."device/google/crosshatch".patches = [ (./. + "/${toString config.androidVersion}/crosshatch-fix-device-names.patch") ];
  source.dirs."device/google/bonito".patches = [ (./. + "/${toString config.androidVersion}/bonito-fix-device-names.patch") ];
  source.dirs."device/google/wahoo".postPatch = patchSystemUIGoogle;
  source.dirs."device/google/crosshatch".postPatch = patchSystemUIGoogle;
  source.dirs."device/google/bonito".postPatch = patchSystemUIGoogle;
})
(mkIf (elem config.androidVersion [ 11 ]) {
  source.dirs."device/google/coral".patches = [ (./. + "/${toString config.androidVersion}/coral-fix-device-names.patch") ];
  source.dirs."device/google/sunfish".patches = [ (./. + "/${toString config.androidVersion}/sunfish-fix-device-names.patch") ];
  source.dirs."device/google/coral".postPatch = patchSystemUIGoogle;
  source.dirs."device/google/sunfish".postPatch = patchSystemUIGoogle;
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
# TODO: Build kernels for non marlin/sailfish devices
(mkIf (config.deviceFamily == "taimen" || config.deviceFamily == "muskie") {
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.71";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "crosshatch") {
  kernel.configName = "b1c1";
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.72";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "bonito") {
  kernel.src = kernelSrc {
    rev = "android-10.0.0_r0.73";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "coral") {
  kernel.src = kernelSrc {
    tag = "android-10.0.0_r0.74";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
})
(mkIf (config.deviceFamily == "marlin") {
  warnings = [ "marlin and sailfish are no longer receiving monthly security updates from Google. Support is left just for testing" ];

  apv.buildID = "QP1A.191005.007.A3";
  source.manifest.rev = "android-10.0.0_r41";

  # HACK to use recent android source, but with old vendor files...
  source.dirs."vendor/google_devices".postPatch = ''
    echo QQ3A.200805.001 > ${config.device}/build_id.txt
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
  kernel.useCustom = mkDefault config.signing.enable;
})

]))


### Android 11 stuff ###
(mkIf (config.androidVersion == 11) (mkMerge [
{
  buildDateTime = mkDefault 1600909299; # 2020-09-23

  # Temporarily use a recent upstream prebuilt webview until we use a chromium version that supports API >= 30
  source.dirs."external/chromium-webview".src = pkgs.fetchgit {
    url = "https://github.com/GrapheneOS/platform_external_chromium-webview";
    rev = "7a4cedd75b8842a070f345e991ca595933e64197";
    sha256 = "1fw8r3kvs6nbaykahxj9s4kv21vigpl9cfqzipbwlxgdr83fv7zr";
  };
  webview.prebuilt.enable = true;
  webview.prebuilt.packageName = "com.google.android.webview";
}
(mkIf (config.device != "sunfish") {
  source.manifest.rev = mkDefault "android-11.0.0_r1";
  apv.buildID = mkDefault "RP1A.200720.009";
})
(mkIf (config.device == "sunfish") {
  source.manifest.rev = mkDefault "android-11.0.0_r3";
  apv.buildID = mkDefault "RP1A.200720.011";
})
{
  # See also: https://github.com/GrapheneOS/os_issue_tracker/issues/325
  # List of biometric sensors on the device, in decreasing strength. Consumed by AuthService
  # when registering authenticators with BiometricService. Format must be ID:Modality:Strength,
  # where: IDs are unique per device, Modality as defined in BiometricAuthenticator.java,
  # and Strength as defined in Authenticators.java
  resources."frameworks/base/core/res".config_biometric_sensors =
    optional (elem config.deviceFamily [ "taimen" "muskie" "crosshatch" "bonito" ]) "0:2:15"
    ++ optional (config.deviceFamily == "coral") "0:8:15";
  resourceTypeOverrides."frameworks/base/core/res".config_biometric_sensors = "string-array";
}
]))

])
