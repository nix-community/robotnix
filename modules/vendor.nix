{ config, pkgs, lib, ... }:

# TODO: One possibility is to reimplement parts of android-prepare-vendor in native nix so we can use an android-prepare-vendor config file directly
with lib;
let
  android-prepare-vendor = pkgs.callPackage ../android-prepare-vendor { api = config.apiLevel; };
in
{
  options = {
    vendor.img = mkOption {
      default = null;
      type = types.nullOr types.path;
      description = "A .img from upstream whose vendor contents should be extracted and included in the build";
    };

    vendor.full = mkOption {
      default = false;
      type = types.bool;
      description = "Include non-essential OEM blobs";
    };

    vendor.files = mkOption {
      type = types.path;
      internal = true;
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
    vendor.files = let
      apvConfig = builtins.fromJSON (builtins.readFile "${android-prepare-vendor.android-prepare-vendor}/${config.device}/config.json");
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
        configFile = mergedConfigFile;
      };

    # Just for ease in debugging
    build.vendorUnpacked = android-prepare-vendor.unpackImg {
      inherit (config) device;
      inherit (config.vendor) img;
    };

    # Using unpackScript instead of source.dirs since vendor_overlay/google_devices/${config.device} is not guaranteed to exist
    source.unpackScript = mkAfter ''
      cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.vendor.files}/* .
      chmod u+w -R *
    '';
  };
}
