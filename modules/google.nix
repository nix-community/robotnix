{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.google;
  # Android 10 separates product specific apps/config, but its still under system in marlin
  productPath = if (config.androidVersion >= 10)
    then "${optionalString (config.deviceFamily == "marlin") "system/"}product"
    else "system";
in
{
  # TODO: Add other google stuff. Ensure that either google play services or microg is enabled if these are.
  options = {
    google = {
      base.enable = mkEnableOption "Base Google OEM files";
      dialer.enable = mkEnableOption "Google Dialer";
      fi.enable = mkEnableOption "Google Fi";
    };
  };

  config = mkMerge [
    (mkIf cfg.base.enable {
      vendor.systemBytecode = [
      ];
      vendor.systemOther = [
        "system/etc/permissions/privapp-permissions-google.xml"
        "${productPath}/etc/sysconfig/google_build.xml"
        "${productPath}/etc/sysconfig/google-hiddenapi-package-whitelist.xml"
        "${productPath}/etc/sysconfig/google.xml"
        "${productPath}/etc/sysconfig/nexus.xml"
      ] ++ (optionals (config.androidVersion >= 10) [
        "${productPath}/etc/permissions/privapp-permissions-google-ps.xml"
        "${productPath}/etc/permissions/privapp-permissions-google-p.xml"
      ]) ++ (optionals (config.deviceFamily == "crosshatch") [ # TODO: Do this for other devices
        "${productPath}/etc/sysconfig/pixel_2018_exclusive.xml"
        "${productPath}/etc/sysconfig/pixel_experience_2017.xml"
        "${productPath}/etc/sysconfig/pixel_experience_2018.xml"
      ]);
    })
    (mkIf cfg.dialer.enable {
      google.base.enable = true;
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
      google.base.enable = true;
      google.dialer.enable = true;
      vendor.systemBytecode = [
        "${productPath}/app/Tycho/Tycho.apk::PRESIGNED" # Google Fi app
        "${productPath}/priv-app/GCS/GCS.apk::PRESIGNED" # Google Connectivity Services (does wifi VPN at least)
        "${productPath}/priv-app/CarrierServices/CarrierServices.apk::PRESIGNED" # Google Carrier Services. com.google.android.ims (needed for wifi calls)
        "${productPath}/priv-app/CarrierSettings/CarrierSettings.apk::PRESIGNED" # com.google.android.carrier
        "${productPath}/priv-app/CarrierSetup/CarrierSetup.apk::PRESIGNED" # com.google.android.carriersetup
      ] ++ (optionals (config.deviceFamily == "crosshatch") [ # TODO: Generalize to other devices with esim
        "${productPath}/priv-app/EuiccGoogle/EuiccGoogle.apk::PRESIGNED"
      ]) ++ (optionals ((config.deviceFamily == "crosshatch") && (config.androidVersion >= 10)) [
        "${productPath}/priv-app/EuiccSupportPixel/EuiccSupportPixel.apk::PRESIGNED"
      ]);

      vendor.systemOther = optionals (config.deviceFamily == "crosshatch") [
        "${productPath}/priv-app/Euicc${if (config.androidVersion >= 10) then "SupportPixel" else "Google"}/esim-full-v0.img"
        "${productPath}/priv-app/Euicc${if (config.androidVersion >= 10) then "SupportPixel" else "Google"}/esim-v1.img"
      ];
    })
  ];
}
