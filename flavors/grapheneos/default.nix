# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
{
  options.grapheneos = {
    channel = lib.mkOption {
      type = with lib.types; nullOr (enum [ "alpha" "beta" "stable" ]);
      description = ''
        The GrapheneOS channel to use.
      '';
    };

    release = lib.mkOption {
      type = with lib.types; nullOr str;
      description = ''
        The GrapheneOS release tag to build. Set this if you're building a for
        a non-phone target, or if you didn't select a channel.
      '';
      example = "2025073000";
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
      adevtool.buildID = mkDefault buildIDs."${deviceInfo.git_tag}.lock";
    }))
    {
      release = "cur";
      buildNumber = mkDefault config.grapheneos.release;

      # Match upstream user/hostname
      envVars = {
        BUILD_USERNAME = "grapheneos";
        BUILD_HOSTNAME = "grapheneos";
      };

      adevtool = let
        vendorImgMetadata = lib.importJSON (./. + "/vendor_img_metadata_${config.grapheneos.release}.json");
        vendorBuildID = vendorImgMetadata.vendor_build_id;
        imgFields = lib.splitString " " vendorImgMetadata."${config.device}".build_index_props.factory;
        imgSha256 = builtins.elemAt imgFields 0;
        imgFilename = builtins.elemAt imgFields 1;
      in mkIf (elem config.device phoneDevices) {
        enable = true;
        yarnHash = (lib.importJSON ./yarn_hashes.json)."${config.grapheneos.release}.lock";
        img = pkgs.fetchurl {
          url = "https://dl.google.com/dl/android/aosp/${imgFilename}";
          sha256 = imgSha256;
        };
        inherit imgFilename;
      };

      source.manifest = {
        enable = true;
        lockfile = mkDefault (./. + "/${config.grapheneos.release}.lock");
      };

      warnings = (optional ((config.device != null) && !(elem config.device supportedDevices))
        "${config.device} is not a supported device for GrapheneOS")
        ++ (optional (!(elem config.androidVersion [ 16 ])) "Unsupported androidVersion (!= 16) for GrapheneOS");
    }
    {
      apps.seedvault.includedInFlavor = mkDefault true;
      apps.updater.includedInFlavor = mkDefault true;

      # GrapheneOS just disables apex updating wholesale
      signing.apex.enable = false;

      # Extra packages that should use releasekey
      signing.signTargetFilesArgs = [ "--extra_apks OsuLogin.apk,ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey" ];

      # Leave the existing auditor in the build--just in case the user wants to
      # audit devices running the official upstream build
    }
    ]);
}
