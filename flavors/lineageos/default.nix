# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionals optionalString optionalAttrs
    elem filter
    mapAttrs mapAttrs' nameValuePair filterAttrs
    attrNames getAttrs flatten remove
    mkIf mkMerge mkDefault mkForce
    importJSON toLower hasPrefix removePrefix hasSuffix replaceStrings;

  androidVersionToLineageBranch = {
    "10" = "lineage-17.1";
    "11" = "lineage-18.1";
    "12" = "lineage-19.1";
    "13" = "lineage-20.0";
  };
  lineageBranchToAndroidVersion = mapAttrs' (name: value: nameValuePair value name) androidVersionToLineageBranch;

  deviceMetadata = lib.importJSON ./device-metadata.json;
  LineageOSRelease = androidVersionToLineageBranch.${builtins.toString config.androidVersion};
  repoDirs = lib.importJSON (./. + "/${LineageOSRelease}/repo.json");
  _deviceDirs = importJSON (./. + "/${LineageOSRelease}/device-dirs.json");
  vendorDirs = importJSON (./. + "/${LineageOSRelease}/vendor-dirs.json");

  # TODO: Condition on soc name?
  dtbReproducibilityFix = ''
    sed -i \
      's/^DTB_OBJS := $(shell find \(.*\))$/DTB_OBJS := $(sort $(shell find \1))/' \
      arch/arm64/boot/Makefile
  '';
  kernelsNeedFix = [ # Only verified marlin reproducibility is fixed by this, however these other repos have the same issue
    "kernel/asus/sm8150"
    "kernel/bq/msm8953"
    "kernel/essential/msm8998"
    "kernel/google/marlin"
    "kernel/leeco/msm8996"
    "kernel/lge/msm8996"
    "kernel/motorola/msm8996"
    "kernel/motorola/msm8998"
    "kernel/motorola/sdm632"
    "kernel/nubia/msm8998"
    "kernel/oneplus/msm8996"
    "kernel/oneplus/sdm845"
    "kernel/oneplus/sm8150"
    "kernel/razer/msm8998"
    "kernel/samsung/sdm670"
    "kernel/sony/sdm660"
    "kernel/xiaomi/jason"
    "kernel/xiaomi/msm8998"
    "kernel/xiaomi/sdm660"
    "kernel/xiaomi/sdm845"
    "kernel/yandex/sdm660"
    "kernel/zuk/msm8996"
  ];
  # Patch kernels
  patchKernelDir = n: v: v // (optionalAttrs (hasPrefix "kernel/" n) {
    patches = config.kernel.patches;
    postPatch = config.kernel.postPatch
      + optionalString (config.useReproducibilityFixes && (elem n kernelsNeedFix)) ("\n" + dtbReproducibilityFix);
  });
  deviceDirs = mapAttrs patchKernelDir _deviceDirs;

  supportedDevices = attrNames deviceMetadata;

  # TODO: Move this filtering into vanilla/graphene
  filterDirAttrs = dir: filterAttrs (n: v: elem n ["rev" "sha256" "url" "patches" "postPatch"]) dir;
  filterDirsAttrs = dirs: mapAttrs (n: v: filterDirAttrs v) dirs;
in mkIf (config.flavor == "lineageos")
{
  androidVersion = let
      defaultBranch = deviceMetadata.${config.device}.branch;
    in mkIf (deviceMetadata ? ${config.device}) (mkDefault (lib.toInt lineageBranchToAndroidVersion.${defaultBranch}));
  flavorVersion = removePrefix "lineage-" androidVersionToLineageBranch.${toString config.androidVersion};

  productNamePrefix = "lineage_"; # product names start with "lineage_"

  buildDateTime = mkDefault (import ./lastUpdated.epoch);

  # LineageOS uses this by default. If your device supports it, I recommend using variant = "user"
  variant = mkDefault "userdebug";

  warnings = let
    isUnsupportedDevice = config.device != null && !(elem config.device supportedDevices) && config.deviceFamily != "generic";
    isUnmaintained = lib.versionOlder (toString config.androidVersion) "13";
  in optional isUnsupportedDevice "${config.device} is not an officially-supported device for LineageOS"
     ++ optional isUnmaintained "${LineageOSRelease} is unmaintained in robotnix and may break at any time";

  source.dirs = mkMerge ([
    repoDirs

    {
      "vendor/lineage".patches = [
        (if lib.versionAtLeast (toString config.androidVersion) "13"
         then ./0001-Remove-LineageOS-keys-20.patch
         else ./0001-Remove-LineageOS-keys-19.patch)

        (pkgs.substituteAll {
          src = ./0002-bootanimation-Reproducibility-fix.patch;
          inherit (pkgs) imagemagick;
        })

        (if lib.versionAtLeast (toString config.androidVersion) "13"
         then ./0003-kernel-Set-constant-kernel-timestamp-20.patch
         else ./0003-kernel-Set-constant-kernel-timestamp-19.patch)
        
      ] ++ lib.optionals (lib.versionAtLeast (toString config.androidVersion) "13") [
        ./dont-run-repo-during-build.patch
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
    }
  ] ++ optionals (deviceMetadata ? "${config.device}") (let
    # Device-specific source dirs
    vendor = toLower deviceMetadata.${config.device}.vendor;
    deviceRelpath = "device/${vendor}/${config.device}";

    # Retuns a list of all relpaths for the device (including deps) recursively
    relpathWithDeps = relpath: [ relpath ] ++ (
      flatten (map (p: relpathWithDeps p) deviceDirs.${relpath}.deps)
    );
    # All relpaths required by the device
    relpaths = relpathWithDeps deviceRelpath;
    filteredRelpaths = remove (attrNames repoDirs) relpaths; # Remove any repos that we're already including from repo json

    # In LOS20, each device/ relpath has an associated vendor/ relpath.
    # Well, usually...
    deviceRelpaths = filter (path: hasPrefix "device/" path) relpaths;
    vendorifiedRelpaths = map (replaceStrings [ "device/" ] [ "vendor/" ]) deviceRelpaths;

    vendorRelpaths = if config.androidVersion >= 13 then (
      # LOS20 needs vendor/$vendor/$device and all the common dirs but with
      # vendor/ prefix
      vendorifiedRelpaths
    ) else [
      # Older LOS need this
      "vendor/${vendor}"
    ];
  in [
    (filterDirsAttrs (getAttrs (filteredRelpaths) deviceDirs))
    (filterDirsAttrs (getAttrs (vendorRelpaths) vendorDirs))
  ]));

  source.manifest.url = mkDefault "https://github.com/LineageOS/android.git";
  source.manifest.rev = mkDefault "refs/heads/${LineageOSRelease}";

  # Enable robotnix-built chromium / webview
  apps.chromium.enable = mkDefault true;
  webview.chromium.availableByDefault = mkDefault true;
  webview.chromium.enable = mkDefault true;

  # This is the prebuilt webview apk from LineageOS. Adding this here is only
  # for convenience if the end-user wants to set `webview.prebuilt.enable = true;`.
  webview.prebuilt.apk = if config.androidVersion >= 11 then
    config.source.dirs."external/chromium-webview/prebuilt/${config.arch}".src + "/webview.apk"
  else
    config.source.dirs."external/chromium-webview".src + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;
  removedProductPackages = [ "webview" ];

  apps.updater.flavor = mkDefault "lineageos";
  apps.updater.includedInFlavor = mkDefault true;
  apps.seedvault.includedInFlavor = mkDefault true;
  pixel.activeEdge.includedInFlavor = mkDefault true;

  # Needed by included kernel build for some devices (pioneer at least)
  envPackages = [ pkgs.openssl.dev ] ++ optionals (config.androidVersion >= 11) [ pkgs.gcc.cc pkgs.glibc.dev ];

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL";  # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # LineageOS flattens all APEX packages: https://review.lineageos.org/c/LineageOS/android_vendor_lineage/+/270212
  signing.apex.enable = false;
  # This environment variable is set in android/build.sh under https://github.com/lineageos-infra/build-config
  envVars.OVERRIDE_TARGET_FLATTEN_APEX = "true";

  # LineageOS needs this additional command line argument to enable
  # backuptool.sh, which runs scripts under /system/addons.d
  otaArgs = [ "--backup=true" ];
}
