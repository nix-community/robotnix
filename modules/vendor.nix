{ config, pkgs, lib, ... }:

# TODO: One possibility is to reimplement parts of android-prepare-vendor in native nix so we can use an android-prepare-vendor config file directly
with lib;
let
  android-prepare-vendor = pkgs.callPackage ../android-prepare-vendor { api = config.apiLevel; };
  apvConfig = builtins.fromJSON (builtins.readFile "${android-prepare-vendor.android-prepare-vendor}/${config.device}/config.json");
  usedOta = if (apvConfig ? ota-partitions) then config.vendor.ota else null;
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

    vendor.full = mkOption {
      default = false;
      type = types.bool;
      description = "Include non-essential OEM blobs";
    };

    vendor.systemBytecode = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    vendor.systemOther = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  config = mkIf (config.vendor.img != null) {
    build.vendor = {
      files = let
        # TODO: There's probably a better way to do this
        mergedConfig = recursiveUpdate apvConfig {
          "api-${config.apiLevel}".${if config.vendor.full then "full" else "naked"} = let
            _config = apvConfig."api-${config.apiLevel}".${if config.vendor.full then "full" else "naked"};
          in _config // {
            system-bytecode = _config.system-bytecode ++ config.vendor.systemBytecode;
            system-other = _config.system-other ++ config.vendor.systemOther;
          };
        };
        mergedConfigFile = builtins.toFile "config.json" (builtins.toJSON mergedConfig);
      in
        android-prepare-vendor.buildVendorFiles {
          inherit (config) device;
          inherit (config.vendor) img full;
          ota = usedOta;
          configFile = mergedConfigFile;
        };

      # Just for ease in debugging
      unpacked = android-prepare-vendor.unpackImg {
        inherit (config) device;
        inherit (config.vendor) img;
      };

      # For debugging differences between upstream vendor files and ours
      # TODO: Could probably compare with something earlier in the process.
      # It's also a little dumb that this does buildVendorFiles and unpackImg on config.vendor.img
      diff = let
          builtVendor = android-prepare-vendor.unpackImg {
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

    # Using unpackScript instead of source.dirs since vendor_overlay/google_devices/${config.device} is not guaranteed to exist
    source.unpackScript = mkAfter ''
      cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.build.vendor.files}/* .
      chmod u+w -R *
    '';
  };
}
