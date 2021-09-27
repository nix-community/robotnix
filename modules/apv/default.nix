# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

# Android-prepare-vendor is currently only useful for Pixel phones

let
  inherit (lib) mkIf mkOption mkEnableOption types;

  cfg = config.apv;

  apiStr = builtins.toString config.apiLevel;
  android-prepare-vendor = pkgs.android-prepare-vendor.override { api = config.apiLevel; };

  configFile = "${android-prepare-vendor.evalTimeSrc}/${config.device}/config.json";
  apvConfig = builtins.fromJSON (builtins.readFile configFile);
  replacedApvConfig = lib.recursiveUpdate apvConfig config.apv.customConfig;

  filterConfig = _config: _config // {
    system-bytecode = _config.system-bytecode ++ cfg.systemBytecode;
    # We don't use the apns-conf.xml generator currently
    # system/product workaround needed for taimen
    system-other = (lib.filter (n: n != "system/product/etc/apns-conf.xml") _config.system-other) ++ cfg.systemOther;
  } // lib.optionalAttrs (_config ? product-other) {
    # We don't use the apns-conf.xml generator currently
    product-other = lib.filter (n: n != "product/etc/apns-conf.xml") _config.product-other;
  };

  # TODO: There's probably a better way to do this
  mergedConfig = lib.recursiveUpdate replacedApvConfig (
    if (config.flavor == "grapheneos")
    then filterConfig replacedApvConfig
    else { "api-${apiStr}".naked = filterConfig replacedApvConfig."api-${apiStr}".naked; }
  );
  mergedConfigFile = builtins.toFile "config.json" (builtins.toJSON mergedConfig);

  # Original function used for creating vendor files. Left here for debugging
  buildVendorFiles =
    { device, img, ota ? null, full ? false, timestamp ? 1, buildID ? "robotnix", configFile ? null }:
    pkgs.runCommand "vendor-files-${device}" {} ''
      ${android-prepare-vendor}/execute-all.sh \
        ${lib.optionalString full "--full"} \
        --yes \
        --output . \
        --device "${device}" \
        --buildID "${buildID}" \
        --imgs "${img}" \
        ${lib.optionalString (ota != null) "--ota ${ota}"} \
        ${lib.optionalString (config.flavor != "grapheneos") "--debugfs"} \
        ${lib.optionalString (config.flavor != "grapheneos") "--timestamp \"${builtins.toString timestamp}\""} \
        ${lib.optionalString (configFile != null) "--conf-file ${configFile}"}

      mkdir -p $out
      cp -r ${device}/${buildID}/* $out
    '';

  unpackImg = img: pkgs.runCommand "unpacked-img-${config.device}-${cfg.buildID}" {} ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-factory-images.sh \
        --input "${img}" \
        --output $out \
        ${lib.optionalString (config.flavor != "grapheneos") "--debugfs"} \
        --conf-file ${mergedConfigFile}
    '';

  unpackOta = ota: pkgs.runCommand "unpacked-ota-${config.device}-${cfg.buildID}" {} ''
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
      default = [];
      internal = true;
    };

    systemOther = mkOption {
      type = types.listOf types.str;
      default = [];
      internal = true;
    };

    buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
    };

    customConfig = mkOption {
      type = types.attrs;
      default = {};
      internal = true;
      description = "Replacement apv JSON to use instead of upstream";
    };
  };

  config = {
    build.apv = {
      origfiles =
        buildVendorFiles {
          inherit (config) device;
          inherit (cfg) img ota;
          configFile = mergedConfigFile;
        };

      unpackedImg = unpackImg cfg.img;
      unpackedOta = unpackOta cfg.ota;

      repairedSystem = pkgs.runCommand "repaired-system-${config.device}-${cfg.buildID}" {} ''
          mkdir -p $out
          ${android-prepare-vendor}/scripts/system-img-repair.sh \
            --input ${config.build.apv.unpackedImg}/system/system \
            --output $out \
            --method OATDUMP \
            --oatdump ${android-prepare-vendor}/hostTools/Linux/api-${apiStr}/bin/oatdump \
            ${lib.optionalString (config.flavor != "grapheneos") "--timestamp 1"}
        '';

      files = pkgs.runCommand "vendor-files-${config.device}-${cfg.buildID}" {} (with config.build.apv; ''
        mkdir -p tmp
        ln -s ${repairedSystem}/system tmp/system

        # See "execute-all.sh" of android-prepare-vendor:

        ln -s ${unpackedImg}/vendor tmp/vendor
        if [[ -d ${unpackedImg}/product ]]; then
          ln -s ${unpackedImg}/product tmp/product
        fi
        if [[ -d ${unpackedImg}/system_ext ]]; then
          ln -s ${unpackedImg}/system_ext tmp/system_ext
        fi

        cp ${unpackedImg}/vendor_partition_size tmp
        if [[ -f ${unpackedImg}/product_partition_size ]]; then
          cp ${unpackedImg}/product_partition_size tmp
        fi

        mkdir -p tmp/radio
        cp -r ${unpackedImg}/radio tmp/
        cp -r ${unpackedOta}/radio tmp/

        ${android-prepare-vendor}/scripts/gen-prop-blobs-list.sh \
          --input ${unpackedImg}/vendor \
          --output . \
          ${lib.optionalString (config.flavor != "grapheneos") "--api ${apiStr}"} \
          --conf-file ${mergedConfigFile} \
          ${lib.optionalString (config.flavor != "grapheneos") "--conf-type naked"}

        mkdir -p $out
        ${android-prepare-vendor}/scripts/generate-vendor.sh \
          --input $(pwd)/tmp \
          --output $out \
          ${lib.optionalString (config.flavor != "grapheneos") "--api ${apiStr}"} \
          --conf-file ${mergedConfigFile} \
          ${lib.optionalString (config.flavor != "grapheneos") "--conf-type naked"} \
          ${lib.optionalString (config.flavor != "grapheneos") "--allow-preopt"}
      '');

      # For debugging differences between upstream vendor files and ours
      diff = let
        unpackedUpstream = pkgs.robotnix.unpackImg config.apv.img;
        unpackedBuilt = pkgs.robotnix.unpackImg config.build.factoryImg;
      in pkgs.runCommand "apv-diff" { nativeBuildInputs = [ pkgs.binutils ]; } ''
        mkdir -p $out
        ln -s ${unpackedUpstream} $out/upstream
        ln -s ${unpackedBuilt} $out/built

        find ${unpackedUpstream} -type f -printf "%P\n" | sort > $out/upstream-files
        find ${unpackedBuilt} -type f -printf "%P\n" | sort > $out/built-files
        diff -u $out/upstream-files $out/built-files > $out/diff || true
      '';
        #bash ${./apv-lib-check.sh} $out/built-files $out/upstream-files | sort > $out/shared-libs-report.txt
    };

    # TODO: Re-add support for vendor_overlay if it is ever used again
    source.dirs = mkIf cfg.enable {
      "vendor/google_devices".src = "${config.build.apv.files}/vendor/google_devices";
    };
  };
}
