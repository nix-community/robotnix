{ config, pkgs, lib, ... }:


with lib;
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
      description = "Include non-essential OEM blobs to be compatible with GApps";
    };

    vendor.files = mkOption {
      type = types.path;
      internal = true;
    };
  };

  config = mkIf (config.vendor.img != null) {
    vendor.files = pkgs.callPackage ./android-prepare-vendor {
      inherit (config) device;
      inherit (config.vendor) img full;
    };

    # Using unpackScript instead of source.dirs since vendor_overlay/google_devices/${config.device} is not guaranteed to exist
    source.unpackScript = mkAfter ''
      cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.vendor.files}/* .
      chmod u+w -R *
    '';
  };
}
