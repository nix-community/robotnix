{ config, pkgs, lib, ... }:

# Robotnix module for android-prepare-vendor (apv)

with lib;
let
  cfg = config.apv;

  apiStr = builtins.toString config.apiLevel;
  android-prepare-vendor = pkgs.android-prepare-vendor.override { api = config.apiLevel; };

  configFile = android-prepare-vendor.src + "/${config.device}/config.json";
  apvConfig = builtins.fromJSON (builtins.readFile configFile);

  # TODO: There's probably a better way to do this
  mergedConfig = recursiveUpdate apvConfig {
    "api-${apiStr}".naked = let
      _config = apvConfig."api-${apiStr}".naked;
    in _config // {
      system-bytecode = _config.system-bytecode ++ cfg.systemBytecode;
      system-other = _config.system-other ++ cfg.systemOther;
    };
  };
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
        --debugfs \
        --timestamp "${builtins.toString timestamp}" \
        ${lib.optionalString (configFile != null) "--conf-file ${configFile}"}

      mkdir -p $out
      cp -r ${device}/${buildID}/* $out
    '';

  unpackImg = img: pkgs.runCommand "unpacked-img-${config.device}-${cfg.buildID}" {} ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-factory-images.sh \
        --input "${img}" \
        --output $out \
        --debugfs  \
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
      description = "A factory image .zip from upstream whose vendor contents should be extracted and included in the build";
    };

    ota = mkOption {
      default = null;
      type = types.path;
      description = "An ota from upstream whose vendor contents should be extracted and included in the build (Android 10 builds need an OTA as well)";
    };

    systemBytecode = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    systemOther = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
      internal = true;
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

      repairedSystem = let
        bytecodeList = pkgs.writeText "bytecode_list.txt"
          (concatStringsSep "\n" (with apvConfig."api-${apiStr}".naked; system-bytecode ++ product-bytecode));
      in
        pkgs.runCommand "repaired-system-${config.device}-${cfg.buildID}" {} ''
          mkdir -p $out
          ${android-prepare-vendor}/scripts/system-img-repair.sh \
            --input ${config.build.apv.unpackedImg}/system/system \
            --output $out \
            --method OATDUMP \
            --oatdump ${android-prepare-vendor}/hostTools/Linux/api-${apiStr}/bin/oatdump \
            --bytecode-list ${bytecodeList} \
            --timestamp 1
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
          --api ${apiStr} \
          --conf-file ${mergedConfigFile} \
          --conf-type naked

        mkdir -p $out
        ${android-prepare-vendor}/scripts/generate-vendor.sh \
          --input $(pwd)/tmp \
          --output $out \
          --api ${apiStr} \
          --conf-file ${mergedConfigFile} \
          --conf-type naked \
          ${optionalString (config.flavor != "grapheneos") "--allow-preopt"}
      '');

      # For debugging differences between upstream vendor files and ours
      diff = let
          builtVendor = unpackImg config.factoryImg;
        in pkgs.runCommand "vendor-diff" {} ''
          mkdir -p $out
          ln -s ${config.build.apv.unpackedImg} $out/upstream
          ln -s ${builtVendor} $out/built
          find ${config.build.apv.unpackedImg}/vendor -printf "%P\n" | sort > $out/upstream-vendor
          find ${builtVendor}/vendor -printf "%P\n" | sort > $out/built-vendor
          diff -u $out/upstream-vendor $out/built-vendor > $out/diff-vendor || true
          find ${config.build.apv.unpackedImg}/system -printf "%P\n" | sort > $out/upstream-system
          find ${builtVendor}/system -printf "%P\n" | sort > $out/built-system
          diff -u $out/upstream-system $out/built-system > $out/diff-system || true
        '';
    };

    # TODO: Re-add support for vendor_overlay if it is ever used again
    source.dirs = mkIf cfg.enable {
      "vendor/google_devices".src = "${config.build.apv.files}/vendor/google_devices";
    };
  };
}
