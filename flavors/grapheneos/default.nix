# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
{
  options.grapheneos = {
    channel = lib.mkOption {
      type = with lib.types; nullOr (enum [ "alpha" "beta" "stable" ]);
    };

    release = lib.mkOption {
      type = with lib.types; nullOr str;
    };
  };

  config = 
    let
      inherit (lib)
        optional optionalString optionalAttrs elem
        mkIf mkMerge mkDefault mkForce;

      phoneDevices = lib.importJSON ./devices.json;
      supportedDevices = phoneDevices ++ [ "generic" ];
      channelInfo = lib.importJSON ./channel_info.json;
      buildIDs = lib.importJSON ./build_ids.json;
    in mkIf (config.flavor == "grapheneos") (mkMerge [
      (mkIf ((config.grapheneos.channel != null) && (config.device != null) && (builtins.hasAttr config.device channelInfo.device_info."${config.grapheneos.channel}")) (
    let
      deviceInfo = channelInfo.device_info.${config.grapheneos.channel}.${config.device};
    in {
      grapheneos.release = mkDefault deviceInfo.git_tag;
      buildDateTime = mkDefault deviceInfo.build_time;
      apv.buildID = mkDefault buildIDs."${deviceInfo.git_tag}.lock";
    }))
    {
      buildNumber = mkDefault config.grapheneos.release;
      productNamePrefix = mkDefault "";

      # Match upstream user/hostname
      envVars = {
        BUILD_USERNAME = "grapheneos";
        BUILD_HOSTNAME = "grapheneos";
      };

      apv.enable = mkIf (elem config.device phoneDevices) (mkDefault true);

      source.manifest = {
        enable = true;
        lockfile = mkDefault (./. + "/${config.grapheneos.release}.lock");
      };

      warnings = (optional ((config.device != null) && !(elem config.device supportedDevices))
        "${config.device} is not a supported device for GrapheneOS")
        ++ (optional (!(elem config.androidVersion [ 16 ])) "Unsupported androidVersion (!= 16) for GrapheneOS");
    }
    {
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
      nixpkgs.overlays = [ (self: super: {
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
      }) ];

      # GrapheneOS just disables apex updating wholesale
      signing.apex.enable = false;

      # Extra packages that should use releasekey
      signing.signTargetFilesArgs = [ "--extra_apks OsuLogin.apk,ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey" ];

      # Leave the existing auditor in the build--just in case the user wants to
      # audit devices running the official upstream build
    }
    ]);
}
