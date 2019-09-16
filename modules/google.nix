{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.google;
  # Android 10 separates product specific apps/config, but its still under system in marlin
  productPath = if (config.androidVersion == "10")
    then "${optionalString (config.deviceFamily == "marlin") "system/"}product"
    else "system";
in
{
  # TODO: Add other google stuff. Ensure that either google play services or microg is enabled if these are.
  options = {
    google = {
      dialer.enable = mkEnableOption "Google Dialer";
      fi.enable = mkEnableOption "Google Fi";
    };
  };

  # privapp-permissions-google.xml is already included with vendor.full
  config = mkMerge [
    (mkIf cfg.dialer.enable {
      vendor.full = true;
      resources."frameworks/base/core/res" = { 
        config_defaultDialer = "com.google.android.dialer";
        config_priorityOnlyDndExemptPackages = [ "com.google.android.dialer" ]; # Found under PixelConfigOverlayCommon.apk
      };
      vendor.systemBytecode = [
        "${productPath}/priv-app/GoogleDialer/GoogleDialer.apk::PRESIGNED"
        "${productPath}/framework/com.google.android.dialer.support.jar"
      ];
      vendor.systemOther = [
        "${productPath}/etc/permissions/com.google.android.dialer.support.xml"
      ];
    })
    (mkIf cfg.fi.enable {
      vendor.full = true;
      google.dialer.enable = true;
      vendor.systemBytecode = [
        "${productPath}/app/Tycho/Tycho.apk::PRESIGNED" # Google Fi app
        "${productPath}/priv-app/GCS/GCS.apk::PRESIGNED" # Google Connectivity Services (does wifi VPN at least)
        "${productPath}/priv-app/CarrierServices/CarrierServices.apk::PRESIGNED" # Google Carrier Services (seems to be needed for wifi calls)
      ];
    })
  ];
}
