# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

# Android-prepare-vendor is currently only useful for Pixel phones

let
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  cfg = config.apv;

  apiStr = builtins.toString config.apiLevel;
  android-prepare-vendor = pkgs.android-prepare-vendor.override { api = config.apiLevel; };

  configFile = "${android-prepare-vendor.evalTimeSrc}/${config.device}/config.json";
  apvConfig = builtins.fromJSON (builtins.readFile configFile);
  replacedApvConfig = lib.recursiveUpdate apvConfig config.apv.customConfig;

  filterConfig =
    _config:
    _config
    // {
      system-bytecode = _config.system-bytecode ++ cfg.systemBytecode;
      system-other = _config.system-other ++ cfg.systemOther;
    }
    // lib.optionalAttrs (_config ? product-other) { product-other = _config.product-other; };

  # TODO: There's probably a better way to do this
  mergedConfig = lib.recursiveUpdate replacedApvConfig (
    if (config.androidVersion >= 12 || config.flavor == "grapheneos") then
      filterConfig replacedApvConfig
    else
      { "api-${apiStr}".naked = filterConfig replacedApvConfig."api-${apiStr}".naked; }
  );
  mergedConfigFile = builtins.toFile "config.json" (builtins.toJSON mergedConfig);

  latestTelephonyProvider = pkgs.fetchgit {
    inherit (lib.importJSON ./latest-telephony-provider.json) url rev sha256;
  };

  buildVendorFiles =
    {
      device,
      img,
      ota ? null,
      full ? false,
      timestamp ? 1,
      buildID ? "robotnix",
      configFile ? null,
    }:
    pkgs.runCommand "vendor-files-${device}" { } ''
      # Copy source files since scripts assume that script directories are writable
      cp -r ${android-prepare-vendor} apv
      chmod -R u+w apv

      apv/execute-all.sh \
        ${lib.optionalString full "--full"} \
        --yes \
        --output . \
        --device "${device}" \
        --buildID "${buildID}" \
        --imgs "${img}" \
        ${
          lib.optionalString (
            config.androidVersion >= 11
          ) "--carrier-list-folder ${latestTelephonyProvider}/assets/latest_carrier_id"
        } \
        ${lib.optionalString (ota != null) "--ota ${ota}"} \
        ${lib.optionalString (config.flavor == "vanilla" && config.androidVersion < 12) "--debugfs"} \
        ${
          lib.optionalString (
            config.flavor == "vanilla" && config.androidVersion < 12
          ) "--timestamp \"${builtins.toString timestamp}\""
        } \
        ${lib.optionalString (configFile != null) "--conf-file ${configFile}"}

      mkdir -p $out
      cp -r ${device}/${buildID}/* $out
    '';

  unpackImg =
    img:
    pkgs.runCommand "unpacked-img-${config.device}-${cfg.buildID}" { } ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-factory-images.sh \
        --input "${img}" \
        --output $out \
        ${lib.optionalString (config.flavor == "vanilla" && config.androidVersion < 12) "--debugfs"} \
        --conf-file ${mergedConfigFile}
    '';

  unpackOta =
    ota:
    pkgs.runCommand "unpacked-ota-${config.device}-${cfg.buildID}" { } ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-ota.sh \
        --input "${ota}" \
        --output $out \
        --conf-file ${mergedConfigFile}
    '';
in
{
  options.apv = {
    enable = mkEnableOption "android-prepare-vendor";

    img = mkOption {
      default = null;
      type = types.path;
      description = "A factory image `.zip` from upstream whose vendor contents should be extracted and included in the build";
    };

    ota = mkOption {
      default = null;
      type = types.path;
      description = "An `OTA` from upstream whose vendor contents should be extracted and included in the build. (Android >=10 builds require this in addition to `apv.img`)";
    };

    systemBytecode = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
    };

    systemOther = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
    };

    buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
    };

    customConfig = mkOption {
      type = types.attrs;
      default = { };
      internal = true;
      description = "Replacement apv JSON to use instead of upstream";
    };
  };

  config = {
    build.apv = {
      files = buildVendorFiles {
        inherit (config) device;
        inherit (cfg) img ota;
        configFile = mergedConfigFile;
      };

      unpackedImg = pkgs.robotnix.unpackImg cfg.img;
    };

    # TODO: Re-add support for vendor_overlay if it is ever used again
    source.dirs = mkIf cfg.enable {
      "vendor/google_devices".src = "${config.build.apv.files}/vendor/google_devices";
    };
  };
}
