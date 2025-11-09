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

    officialBuild = lib.mkEnableOption "the OFFICIAL_BUILD=true env var (to include the updater)";
  };

  config = 
    let
      inherit (lib)
        optional optionalString optionalAttrs elem
        mkIf mkMerge mkDefault mkForce;

      # The first letter of the build ID represents the Android platform release, see
      # https://source.android.com/docs/setup/reference/build-numbers
      buildIDCodenameInitialToPlatformRelease = {
        "S" = 12;
        "T" = 13;
        "U" = 14;
        "A" = 15;
        "B" = 16;
      };

      phoneDevices = lib.importJSON ./devices.json;
      supportedDevices = phoneDevices ++ [ "generic" ];
      channelInfo = lib.importJSON ./channel_info.json;
      buildIDs = lib.importJSON ./build_ids.json;
    in mkIf (config.flavor == "grapheneos") (mkMerge [
      (mkIf ((config.grapheneos.channel != null) && (config.device != null) && (builtins.hasAttr config.device channelInfo.device_info."${config.grapheneos.channel}")) (
    let
      deviceInfo = channelInfo.device_info.${config.grapheneos.channel}.${config.device};
      buildID = buildIDs."${deviceInfo.git_tag}/repo.lock";
    in {
      assertions = [
        {
          assertion = config.grapheneos.officialBuild -> config.apps.updater.enable;
          message = ''
            If you enable the updater app via the OFFICIAL_BUILD=true env var,
            you must use the Robotnix updater app module to set a custom
            updater URL, or, to quote the official GrapheneOS docs, you will
            "essentially perform a denial of service attack on our update
            service" - presumably because the updater app keeps querying for
            updates if the signatures don't match.
          '';
        }
      ];

      grapheneos.release = mkDefault deviceInfo.git_tag;
      buildDateTime = mkDefault deviceInfo.build_time;
      androidVersion = mkDefault buildIDCodenameInitialToPlatformRelease.${builtins.substring 0 1 buildID};
    }))
    {
      release = "cur";
      productNamePrefix = "";
      buildNumber = mkDefault config.grapheneos.release;

      # Match upstream user/hostname
      envVars = {
        BUILD_USERNAME = "grapheneos";
        BUILD_HOSTNAME = "grapheneos";
        OFFICIAL_BUILD = if config.grapheneos.officialBuild then "true" else "false";
      };

      adevtool = let
        vendorImgMetadata = lib.importJSON (./. + "/${config.grapheneos.release}/vendor_img_metadata.json");
        vendorBuildID = vendorImgMetadata.vendor_build_id;
        imgFields = lib.splitString " " vendorImgMetadata."${config.device}".build_index_props.factory;
        imgSha256 = builtins.elemAt imgFields 0;
        imgFilename = builtins.elemAt imgFields 1;
      in mkIf (elem config.device phoneDevices) {
        enable = true;
        yarnHash = (lib.importJSON ./yarn_hashes.json).${config.grapheneos.release};
        devices = [ config.device ];
        vendorImgs = lib.importJSON ./${config.grapheneos.release}/vendor_imgs/${config.device}.json;
      };

      source.manifest = {
        enable = true;
        lockfile = mkDefault (./. + "/${config.grapheneos.release}/repo.lock");
      };

      source.dirs."vendor/adevtool".patches = lib.optional (!lib.versionAtLeast config.grapheneos.release "2025090300") (
        ./adevtool-ignore-EINVAL-upon-chown.patch
      );

      warnings = (optional ((config.device != null) && !(elem config.device supportedDevices))
        "${config.device} is not a supported device for GrapheneOS")
        ++ (optional (!(elem config.androidVersion [ 16 ])) "Unsupported androidVersion (!= 16) for GrapheneOS");
    }
    {
      apps.seedvault.includedInFlavor = mkDefault true;
      apps.updater.includedInFlavor = mkDefault true;

      source.dirs."packages/apps/Updater".patches = [
        ./dont-show-security-preview-channel-notification.patch
      ];

      # GrapheneOS used to disable APEX completely.
      # It was enabled for all devices sometime during Android 13.
      # https://grapheneos.org/releases#2023051600
      # https://github.com/GrapheneOS/script/blob/6072d9d75c3a22f6cbc33c9ba85129513306ca00/release.sh#L68
      signing = {
        apex.enable = config.androidVersion >= 13;

        # Key for GmsCompatLib.apk
        # https://grapheneos.org/releases#2025102300
        keyMappings = lib.mkIf (lib.versionAtLeast config.grapheneos.release "2025102300") {
          "build/make/target/product/security/gmscompat_lib" = "${config.device}/gmscompat_lib";
        };

        # Extra packages that should use releasekey
        signTargetFilesArgs = [ "--extra_apks OsuLogin.apk,ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey" ];
      };

      # Leave the existing auditor in the build--just in case the user wants to
      # audit devices running the official upstream build
    }
    ]);
}
