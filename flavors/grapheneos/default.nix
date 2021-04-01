# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
with lib;
let
  grapheneOSRelease = "${config.apv.buildID}.2021.03.19.14";

  phoneDeviceFamilies = [ "crosshatch" "bonito" "coral" "sunfish" "redfin" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

in mkIf (config.flavor == "grapheneos") (mkMerge [
{
  # This a default datetime for robotnix that I update manually whenever
  # a significant change is made to anything the build depends on. It does not
  # match the datetime used in the GrapheneOS build above.
  buildDateTime = mkDefault 1616259246;

  source.dirs = lib.importJSON (./. + "/repo-${grapheneOSRelease}.json");

  apv.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
  apv.buildID = mkDefault "RQ2A.210305.006";

  # Not strictly necessary for me to set these, since I override the source.dirs above
  source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  warnings = (optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for GrapheneOS")
    ++ (optional (config.androidVersion != 11) "Unsupported androidVersion (!= 11) for GrapheneOS");
}
{
  # Disable setting SCHED_BATCH in soong. Brings in a new dependency and the nix-daemon could do that anyway.
  source.dirs."build/soong".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_build_soong/commit/76723b5745f08e88efa99295fbb53ed60e80af92.patch";
      sha256 = "0vvairss3h3f9ybfgxihp5i8yk0rsnyhpvkm473g6dc49lv90ggq";
      revert = true;
    })
  ];

  # No need to include these in AOSP build source since we build separately
  source.dirs."kernel/google/marlin".enable = false;
  source.dirs."kernel/google/wahoo".enable = false;
  source.dirs."kernel/google/crosshatch".enable = false;
  source.dirs."kernel/google/bonito".enable = false;
  source.dirs."kernel/google/coral".enable = false;
  source.dirs."kernel/google/sunfish".enable = false;
  source.dirs."kernel/google/redbull".enable = false;

  # Enable Vanadium (GraphaneOS's chromium fork).
  apps.vanadium.enable = mkDefault true;
  webview.vanadium.enable = mkDefault true;
  webview.vanadium.availableByDefault = mkDefault true;

  apps.seedvault.enable = mkDefault true;

  # Remove upstream prebuilt versions from build. We build from source ourselves.
  removedProductPackages = [ "TrichromeWebView" "TrichromeChrome" "webview" "Seedvault" ];
  source.dirs."external/vanadium".enable = false;
  source.dirs."external/seedvault".enable = false;

  # Override included android-prepare-vendor, with the exact version from
  # GrapheneOS. Unfortunately, Doing it this way means we don't cache apv
  # output across vanilla/grapheneos, even if they are otherwise identical.
  source.dirs."vendor/android-prepare-vendor".enable = false;
  nixpkgs.overlays = [ (self: super: {
    android-prepare-vendor = super.android-prepare-vendor.overrideAttrs (_: {
      src = config.source.dirs."vendor/android-prepare-vendor".src;
      passthru.evalTimeSrc = builtins.fetchTarball {
        url = "https://github.com/GrapheneOS/android-prepare-vendor/archive/${config.source.dirs."vendor/android-prepare-vendor".rev}.tar.gz";
        inherit (config.source.dirs."vendor/android-prepare-vendor") sha256;
      };
    });
  }) ];

  # GrapheneOS just disables apex updating wholesale
  signing.apex.enable = false;

  # Don't include updater by default since it would download updates signed with grapheneos's keys.
  # TODO: Encourage user to set apps.updater.enable
  source.dirs."packages/apps/Updater".enable = false;

  # Leave the existing auditor in the build--just in case the user wants to
  # audit devices using the official upstream build
}
(mkIf (elem config.deviceFamily phoneDeviceFamilies) {
  kernel.useCustom = mkDefault true;
  kernel.src = mkDefault config.source.dirs."kernel/google/${config.kernel.name}".src;
  kernel.configName = config.device;
  kernel.relpath = "device/google/${config.device}-kernel";
})
{
  # Hackish exceptions
  kernel.src = mkIf (config.deviceFamily == "bonito") (mkForce config.source.dirs."kernel/google/crosshatch".src);
  kernel.configName = mkMerge [
    (mkIf (config.device       == "sargo") (mkForce "bonito"))
    (mkIf (config.deviceFamily == "coral") (mkForce "floral"))
  ];
  kernel.relpath = mkMerge [
    (mkIf (config.device == "sargo") (mkForce "device/google/bonito-kernel"))
  ];
}
])
