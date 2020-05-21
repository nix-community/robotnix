{ config, pkgs, lib, ... }:

# TODO: One possibility is to reimplement parts of android-prepare-vendor in native nix so we can use an android-prepare-vendor config file directly
with lib;
let
  _android-prepare-vendor = pkgs.callPackage ../pkgs/android-prepare-vendor { api = config.apiLevel; };
  android-prepare-vendor =
    if config.flavor == "grapheneos"
    then _android-prepare-vendor.overrideAttrs (attrs: {
      # TODO: Temporarily disable PREOPT for grapheneos
      patches = attrs.patches ++ [
        (pkgs.fetchpatch {
          url = "https://github.com/GrapheneOS/android-prepare-vendor/commit/85d206cc28a6d1c23d3e088238b63bc2e6f68743.patch";
          sha256 = "1nm6wrdqwwk5jdjwyi3na4x6h7midxvdjc31734klf13fysxmcsp";
        })
      ];
    })
    else _android-prepare-vendor;

  apvConfig = builtins.fromJSON (builtins.readFile "${android-prepare-vendor}/${config.device}/config.json");
  usedOta = if (apvConfig ? ota-partitions) then config.vendor.ota else null;

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

  unpackImg =
    { device, img, configFile ? null }:
    pkgs.runCommand "unpacked-img-${device}" {} ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-factory-images.sh --debugfs --input "${img}" --output $out --conf-file ${android-prepare-vendor}/${device}/config.json
    '';

  repairImg = imgDir:
    pkgs.runCommand "repaired-img" {} ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/system-img-repair.sh --input "${imgDir}/system" --output $out --method OATDUMP --oatdump ${android-prepare-vendor}/hostTools/Linux/api-${api}/bin/oatdump
    '';
in
{
  options = {
    vendor.img = mkOption {
      default = null;
      type = types.nullOr types.path;
      description = "A factory image .zip from upstream whose vendor contents should be extracted and included in the build";
    };

    vendor.ota = mkOption {
      default = null;
      type = types.nullOr types.path;
      description = "An ota from upstream whose vendor contents should be extracted and included in the build (Android 10 builds needs an OTA as well)";
    };

    vendor.systemBytecode = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    vendor.systemOther = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    vendor.buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
      internal = true;
    };
  };

  config = mkIf (config.vendor.img != null) {
    build.vendor = {
      files = let
        # TODO: There's probably a better way to do this
        mergedConfig = recursiveUpdate apvConfig {
          "api-${config.apiLevel}".naked = let
            _config = apvConfig."api-${config.apiLevel}".naked;
          in _config // {
            system-bytecode = _config.system-bytecode ++ config.vendor.systemBytecode;
            system-other = _config.system-other ++ config.vendor.systemOther;
          };
        };
        mergedConfigFile = builtins.toFile "config.json" (builtins.toJSON mergedConfig);
      in
        buildVendorFiles {
          inherit (config) device;
          inherit (config.vendor) img;
          ota = usedOta;
          configFile = mergedConfigFile;
        };

      unpacked = unpackImg {
        inherit (config) device;
        inherit (config.vendor) img;
      };

      # For debugging differences between upstream vendor files and ours
      # TODO: Could probably compare with something earlier in the process.
      # It's also a little dumb that this does buildVendorFiles and unpackImg on config.vendor.img
      diff = let
          builtVendor = unpackImg {
            inherit (config) device;
            img = config.factoryImg;
          };
        in pkgs.runCommand "vendor-diff" {} ''
          mkdir -p $out
          ln -s ${config.build.vendor.unpacked} $out/upstream
          ln -s ${builtVendor} $out/built
          find ${config.build.vendor.unpacked}/vendor -printf "%P\n" | sort > $out/upstream-vendor
          find ${builtVendor}/vendor -printf "%P\n" | sort > $out/built-vendor
          diff $out/upstream-vendor $out/built-vendor > $out/diff-vendor || true
          find ${config.build.vendor.unpacked}/system -printf "%P\n" | sort > $out/upstream-system
          find ${builtVendor}/system -printf "%P\n" | sort > $out/built-system
          diff $out/upstream-system $out/built-system > $out/diff-system || true
        '';
    };

    # TODO: Re-add support for vendor_overlay if it is ever used again
    source.dirs."vendor/google_devices".src = "${config.build.vendor.files}/vendor/google_devices";
  };
}
