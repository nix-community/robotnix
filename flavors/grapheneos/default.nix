# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault mkForce;

  upstreamParams = import ./upstream-params.nix;
  grapheneOSRelease = "${config.apv.buildID}.${upstreamParams.buildNumber}";

  phoneDeviceFamilies = [ "crosshatch" "bonito" "coral" "sunfish" "redfin" "barbet" "bluejay" "pantah" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];
  kernelPrefix = if config.androidVersion >= 13 then "kernel/android" else "kernel/google";

  kernelRepoName = {
    "sargo" = "crosshatch";
    "bonito" = "crosshatch";
    "flame" = "coral";
    "sunfish" = "coral";
    "bramble" = "redbull";
    "redfin" = "redbull";
    "oriole" = "raviole";
    "raven" = "raviole";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.deviceFamily;
  kernelSourceRelpath = "${kernelPrefix}/${kernelRepoName}";
  kernelSources = lib.mapAttrs'
    (path: src: {
      name = "${kernelSourceRelpath}/${path}";
      value = src // {
        enable = false;
      };
    })
    (lib.importJSON (./kernel-repos/repo- + "${kernelRepoName}-${grapheneOSRelease}.json"));
in
mkIf (config.flavor == "grapheneos") (mkMerge [
  rec {
    androidVersion = mkDefault 13;
    buildNumber = mkDefault upstreamParams.buildNumber;
    buildDateTime = mkDefault upstreamParams.buildDateTime;

    productNamePrefix = mkDefault "";

    # Match upstream user/hostname
    envVars = {
      BUILD_USERNAME = "grapheneos";
      BUILD_HOSTNAME = "grapheneos";
    };
    source.dirs = (lib.importJSON (./. + "/repo-${grapheneOSRelease}.json") // kernelSources);

    # TODO: re-add the legacy devices
    apv.enable = mkIf (config.androidVersion <= 12 && elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
    apv.buildID = mkDefault (if (elem config.device [ "panther" ]) then "TQ2A.230305.008" else
    (if (elem config.device [ "bluejay" ]) then "TQ2A.230305.008.E1" else "TQ2A.230305.008.C1"));
    adevtool.enable = mkIf (config.androidVersion >= 13 && elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
    adevtool.buildID = config.apv.buildID;

    # Not strictly necessary for me to set these, since I override the source.dirs above
    source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

    warnings = (optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
      "${config.device} is not a supported device for GrapheneOS")
    ++ (optional (!(elem config.androidVersion [ 13 ])) "Unsupported androidVersion (!= 13) for GrapheneOS")
    ++ (optional (config.deviceFamily == "crosshatch") "crosshatch/blueline are considered legacy devices and receive only extended support updates from GrapheneOS and no longer receive vendor updates from Google");
  }
  {
    # Upstream tag doesn't always set the BUILD_ID and platform security patch correctly for legacy crosshatch/blueline
    source.dirs."build/make".postPatch = mkIf (elem config.device [ "crosshatch" "blueline" ]) ''
      echo BUILD_ID=SP1A.210812.016.C1 > core/build_id.mk
      sed -i 's/PLATFORM_SECURITY_PATCH := 2021-11-05/PLATFORM_SECURITY_PATCH := 2021-11-01/g' core/version_defaults.mk
    '';

    # Disable setting SCHED_BATCH in soong. Brings in a new dependency and the nix-daemon could do that anyway.
    source.dirs."build/soong".patches = [
      (pkgs.fetchpatch {
        url = "https://github.com/GrapheneOS/platform_build_soong/commit/76723b5745f08e88efa99295fbb53ed60e80af92.patch";
        sha256 = "0vvairss3h3f9ybfgxihp5i8yk0rsnyhpvkm473g6dc49lv90ggq";
        revert = true;
      })
    ];

    # hack to make sure the out directory remains writeable after copying files/directories from /nix/store mounted sources
    source.dirs."prebuilts/build-tools".postPatch = mkIf (config.androidVersion >= 13) ''
      pushd path/linux-x86
      mv cp .cp-wrapped
      cp ${pkgs.substituteAll { src = ./fix-perms.sh; inherit (pkgs) bash; }} cp

      chmod +x cp
      popd
    '';

    # No need to include kernel sources in Android source trees since we build separately
    source.dirs."${kernelPrefix}/marlin".enable = false;
    source.dirs."${kernelPrefix}/wahoo".enable = false;
    source.dirs."${kernelPrefix}/crosshatch".enable = false;
    source.dirs."${kernelPrefix}/bonito".enable = false;
    source.dirs."${kernelPrefix}/coral".enable = false;
    source.dirs."${kernelPrefix}/sunfish".enable = false;
    source.dirs."${kernelPrefix}/redbull".enable = false;
    source.dirs."${kernelPrefix}/barbet".enable = false;
    source.dirs."${kernelPrefix}/bluejay".enable = false;
    source.dirs."${kernelPrefix}/pantah".enable = false;

    kernel.enable = mkDefault (elem config.deviceFamily phoneDeviceFamilies);

    # Enable Vanadium (GraphaneOS's chromium fork).
    apps.vanadium.enable = mkDefault true;
    webview.vanadium.enable = mkDefault true;
    webview.vanadium.availableByDefault = mkDefault true;

    apps.seedvault.includedInFlavor = mkDefault true;
    apps.updater.includedInFlavor = mkDefault true;

    # Remove upstream prebuilt versions from build. We build from source ourselves.
    removedProductPackages = [ "TrichromeWebView" "TrichromeChrome" "webview" ];
    source.dirs."external/vanadium".enable = false;

    # Override included android-prepare-vendor, with the exact version from
    # GrapheneOS. Unfortunately, Doing it this way means we don't cache apv
    # output across vanilla/grapheneos, even if they are otherwise identical.
    source.dirs."vendor/android-prepare-vendor".enable = false;
    nixpkgs.overlays = [
      (self: super: {
        android-prepare-vendor = super.android-prepare-vendor.overrideAttrs (_: {
          src = config.source.dirs."vendor/android-prepare-vendor".src;
          patches = [
            ./apv/0001-Just-write-proprietary-blobs.txt-to-current-dir.patch
            ./apv/0002-Allow-for-externally-set-config-file.patch
            ./apv/0003-Add-option-to-use-externally-provided-carrier_list.p.patch
          ];
          passthru.evalTimeSrc = builtins.fetchTarball {
            url = "https://github.com/GrapheneOS/android-prepare-vendor/archive/${config.source.dirs."vendor/android-prepare-vendor".rev}.tar.gz";
            inherit (config.source.dirs."vendor/android-prepare-vendor") sha256;
          };
        });
      })
    ];

    # GrapheneOS just disables apex updating wholesale
    signing.apex.enable = false;

    # Extra packages that should use releasekey
    signing.signTargetFilesArgs = [
      "--extra_apks AdServicesApk.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks Bluetooth.apk=$KEYSDIR/${config.device}/bluetooth"
      "--extra_apks HalfSheetUX.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks OsuLogin.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks SafetyCenterResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks ServiceConnectivityResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks ServiceUwbResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks WifiDialog.apk=$KEYSDIR/${config.device}/releasekey"
    ];
    # Leave the existing auditor in the build--just in case the user wants to
    # audit devices running the official upstream build
  }
])
