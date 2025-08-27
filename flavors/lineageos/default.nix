# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionals optionalString optionalAttrs
    elem filter
    mapAttrs mapAttrs' nameValuePair filterAttrs
    attrNames getAttrs flatten remove
    mkOption mkIf mkMerge mkDefault mkForce types
    importJSON toLower hasPrefix removePrefix hasSuffix replaceStrings;

  lineageBranchToAndroidVersion = {
    "19.0" = 12;
    "19.1" = 12;
    "20.0" = 13;
    "21.0" = 14;
    "22.0" = 15;
    "22.1" = 15;
    "22.2" = 15;
  };
  deviceMetadata = lib.importJSON ./devices.json;
  supportedDevices = attrNames deviceMetadata;
  missingDepDevices = lib.importJSON (./. + "/lineage-${config.flavorVersion}/missing_dep_devices.json");
in mkIf (config.flavor == "lineageos") {
  assertions = [
    {
      assertion = config.flavorVersion != null;
      message = "The `flavorVersion` config option needs to be set to the LineageOS branch, e.g. `flavorVersion = \"22.2\"`";
    }
    {
      assertion = builtins.hasAttr config.flavorVersion lineageBranchToAndroidVersion;
      message = "Unknown LineageOS branch `${config.flavorVersion}`. Perhaps robotnix doesn't support it yet.";
    }
    {
      assertion = !(builtins.elem config.device missingDepDevices);
      message = "Device `${config.device}` is missing LineageOS device-specific dependencies on branch `${config.flavorVersion}`. This is an upstream issue - most likely, this branch isn't officially supported on this device.";
    }
  ];

  flavorVersion = mkIf (builtins.elem config.device supportedDevices) (mkDefault (lib.removePrefix "lineage-" deviceMetadata.${config.device}.default_branch));

  androidVersion = lineageBranchToAndroidVersion.${config.flavorVersion};
  productNamePrefix = "lineage_"; # product names start with "lineage_"

  # LineageOS uses this by default. If your device supports it, I recommend using variant = "user"
  variant = mkDefault "userdebug";

  source.manifest = {
    enable = true;
    lockfile = ./. + "/lineage-${config.flavorVersion}/repo.lock";
    categories = [ { DeviceSpecific = config.device; } ];
  };

  source.dirs = {
    "vendor/lineage".patches = [
      (if lib.versionAtLeast (toString config.androidVersion) "14"
       then ./0001-Remove-LineageOS-keys-21.patch
       else if lib.versionAtLeast (toString config.androidVersion) "13"
       then ./0001-Remove-LineageOS-keys-20.patch
       else ./0001-Remove-LineageOS-keys-19.patch)

      (pkgs.replaceVars (if lib.versionAtLeast config.flavorVersion "22.2"
        then ./0002-bootanimation-Reproducibility-fix-22_2.patch
        else if lib.versionAtLeast config.flavorVersion "21.1"
        then ./0002-bootanimation-Reproducibility-fix-21.patch else
        ./0002-bootanimation-Reproducibility-fix.patch) {
        inherit (pkgs) imagemagick;
      })

      (if lib.versionAtLeast (toString config.androidVersion) "14"
       then ./0003-kernel-Set-constant-kernel-timestamp-21.patch
       else if lib.versionAtLeast (toString config.androidVersion) "13"
       then ./0003-kernel-Set-constant-kernel-timestamp-20.patch
       else ./0003-kernel-Set-constant-kernel-timestamp-19.patch)
      
    ] ++ lib.optionals (lib.versionAtLeast config.flavorVersion "19.0") [
      (if lib.versionAtLeast config.flavorVersion "22.2"
      then ./0004-dont-run-repo-during-build-22_2.patch
      else ./0004-dont-run-repo-during-build.patch)
    ];
    "system/extras".patches = [
      # pkgutil.get_data() not working, probably because we don't use their compiled python
      (pkgs.fetchpatch {
        url = "https://github.com/LineageOS/android_system_extras/commit/7da4b29321eb7ebce9eb9a43d0fbd85d0aa1e870.patch";
        sha256 = "0pv56lypdpsn66s7ffcps5ykyfx0hjkazml89flj7p1px12zjhy1";
        revert = true;
      })
    ];

    # LineageOS will sometimes force-push to this repo, and the older revisions are garbage collected.
    # So we'll just build chromium webview ourselves.
    "external/chromium-webview".enable = false;
  };

  # This is the prebuilt webview apk from LineageOS. This is the only working
  # webview we have access to (robotnix' own are in disrepair), so this should
  # be used by default unless the user provides another webview themselves.
  webview.prebuilt = {
    enable = mkDefault true;
    apk = config.source.dirs."external/chromium-webview/prebuilt/${config.arch}".src + "/webview.apk";
    availableByDefault = mkDefault true;
  };
  apps.prebuilt.prebuiltwebview.usesOptionalLibraries = lib.mkIf (lib.versionAtLeast config.flavorVersion "22.2") (lib.mkAfter [ "com.android.extensions.xr" ]);
  removedProductPackages = [ "webview" ];

  apps.updater.flavor = mkDefault "lineageos";
  apps.updater.includedInFlavor = mkDefault true;
  apps.seedvault.includedInFlavor = mkDefault true;
  pixel.activeEdge.includedInFlavor = mkDefault true;

  # Needed by included kernel build for some devices (pioneer at least)
  envPackages = [ pkgs.openssl.dev ] ++ optionals (config.androidVersion >= 11) [ pkgs.gcc.cc pkgs.glibc.dev ];

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL";  # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # LineageOS flattens all APEX packages: https://review.lineageos.org/c/LineageOS/android_vendor_lineage/+/270212
  # However, the APEX flattening feature has been removed in LineageOS 21 / Android 14:
  # https://github.com/LineageOS/android_build/commit/5d7f9cb2a1f719fa56572b2a7b7a3c1aa36690ae
  # That means we need to enable APEX signing from Android version 14 onwards.
  signing.apex.enable = config.androidVersion >= 14;
  # This environment variable is set in android/build.sh under https://github.com/lineageos-infra/build-config
  # APEX flattening supported only in Android 13 and earlier.
  envVars.OVERRIDE_TARGET_FLATTEN_APEX = lib.boolToString (config.androidVersion < 14);

  # LineageOS needs this additional command line argument to enable
  # backuptool.sh, which runs scripts under /system/addons.d
  otaArgs = [ "--backup=true" ];
}
