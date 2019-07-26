{ config, pkgs, lib, ... }:


with lib;
let
  vendorImgs = {
    marlin = pkgs.fetchurl {
      url = "https://dl.google.com/dl/android/aosp/marlin-pq3a.190705.001-factory-522f27c4.zip";
      sha256 = "522f27c4d50055f6402ca9d4d62fb07425e3af7c4766b647a4096ce3041984ba";
    };
    crosshatch = pkgs.fetchurl {
      url = "https://dl.google.com/dl/android/aosp/crosshatch-pq3a.190705.003-factory-e59cf7a4.zip";
      sha256 = "e59cf7a412e48d0f78463a67dc0085d98b811026d7c593b8d61925c2d9895e02";
    };
  };
in
{
  options = {
    vendor.img = mkOption {
      default = vendorImgs."${config.deviceFamily}";
      type = types.path;
      description = "A .img from upstream whose vendor contents should be extracted and included in the build";
    };

    vendor.full = mkOption {
      default = false;
      type = types.bool;
      description = "Include non-essential OEM blobs to be compatible with GApps";
    };

    vendor.files = mkOption {
      internal = true;
      default = pkgs.callPackage ../android-prepare-vendor {
        inherit (config) device;
        inherit (config.vendor) img full;
      };
    };
  };

  config = mkIf (config.vendor.img != null) {
    overlays."" = [ config.vendor.files ];
  };
}
