{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.google;

  # TODO: Use repairedImg from android-prepare-vendor
  systemPath = "${unpacked}/system/system";

  # Android 10 separates product specific apps/config, but its still under system in marlin
  productPath = if (config.androidVersion >= 10)
    then "${unpacked}/${optionalString (config.deviceFamily == "marlin") "system/system/"}product"
    else systemPath;

  unpacked = if (config.vendor.img != null)
    then config.build.vendor.unpacked
    else (import ../default.nix { # If vendor is not set--say for generic/emulator targets, use the vendor files from crosshatch
      configuration = {
        device = "crosshatch";
        flavor = "vanilla";
        inherit (config) androidVersion;
      };
    }).build.vendor.unpacked;
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

  # TODO: Refactor to avoid duplicating names (error prone)
  config = mkMerge [
    (mkIf cfg.base.enable {
      etc = {
        "permissions/privapp-permissions-google.xml".source = "${systemPath}/etc/permissions/privapp-permissions-google.xml";
        "sysconfig/google_build.xml".source = "${productPath}/etc/sysconfig/google_build.xml";
        "sysconfig/google-hiddenapi-package-whitelist.xml".source = "${productPath}/etc/sysconfig/google-hiddenapi-package-whitelist.xml";
        "sysconfig/google.xml".source = "${productPath}/etc/sysconfig/google.xml";
        "sysconfig/nexus.xml".source = "${productPath}/etc/sysconfig/nexus.xml";
      } // (optionalAttrs (config.androidVersion >= 10) {
        "permissions/privapp-permissions-google-ps.xml".source = "${productPath}/etc/permissions/privapp-permissions-google-ps.xml";
        "permissions/privapp-permissions-google-p.xml".source = "${productPath}/etc/permissions/privapp-permissions-google-p.xml";
      }) // (optionalAttrs (config.deviceFamily == "marlin") { # TODO: Do this for other devices
        "sysconfig/pixel_2016_exclusive.xml".source = "${systemPath}/etc/sysconfig/pixel_2016_exclusive.xml";
      }) // (optionalAttrs (config.deviceFamily == "crosshatch") { # TODO: Do this for other devices
        "permissions/android.hardware.telephony.euicc.xml".source = "${productPath}/etc/permissions/android.hardware.telephony.euicc.xml";
        "sysconfig/pixel_2018_exclusive.xml".source = "${productPath}/etc/sysconfig/pixel_2018_exclusive.xml";
        "sysconfig/pixel_experience_2017.xml".source = "${productPath}/etc/sysconfig/pixel_experience_2017.xml";
        "sysconfig/pixel_experience_2018.xml".source = "${productPath}/etc/sysconfig/pixel_experience_2018.xml";
      });
    })
    (mkIf cfg.dialer.enable {
      google.base.enable = true;
      resources."frameworks/base/core/res" = { 
        config_defaultDialer = "com.google.android.dialer";
        config_priorityOnlyDndExemptPackages = [ "com.google.android.dialer" ]; # Found under PixelConfigOverlayCommon.apk
      };
      apps.prebuilt.GoogleDialer = {
        apk = "${productPath}/priv-app/GoogleDialer/GoogleDialer.apk";
        privileged = true;
        certificate = "PRESIGNED";
      };
      etc."permissions/com.google.android.dialer.support.xml".source = "${productPath}/etc/permissions/com.google.android.dialer.support.xml";
      framework."com.google.android.dialer.support.jar".source = "${productPath}/framework/com.google.android.dialer.support.jar";
    })
    (mkIf cfg.fi.enable {
      google.base.enable = true;
      google.dialer.enable = true;
      apps.prebuilt = {
        Tycho = {
          apk = "${productPath}/app/Tycho/Tycho.apk"; # Google Fi app
          certificate = "PRESIGNED";
        };
        GCS = {
          apk = "${productPath}/priv-app/GCS/GCS.apk"; # Google Connectivity Services (does wifi VPN at least)
          certificate = "PRESIGNED";
          privileged = true;
        };
        CarrierServices = {
          apk = "${productPath}/priv-app/CarrierServices/CarrierServices.apk"; # Google Carrier Services. com.google.android.ims (needed for wifi calls)
          certificate = "PRESIGNED";
          privileged = true;
        };
        CarrierSettings = {
          apk = "${productPath}/priv-app/CarrierSettings/CarrierSettings.apk"; # com.google.android.carrier
          certificate = "PRESIGNED";
          privileged = true;
        };
        CarrierSetup = {
          apk = "${productPath}/priv-app/CarrierSetup/CarrierSetup.apk"; # com.google.android.carriersetup
          certificate = "PRESIGNED";
          privileged = true;
        };
      } // (optionalAttrs (config.deviceFamily == "crosshatch") { # TODO: Generalize to other devices with esim
        EuiccGoogle = {
          apk = "${productPath}/priv-app/EuiccGoogle/EuiccGoogle.apk";
          certificate = "PRESIGNED";
          privileged = true;
        };
      }) // (optionalAttrs ((config.deviceFamily == "crosshatch") && (config.androidVersion >= 10)) {
        EuiccSupportPixel = {
          apk = "${productPath}/priv-app/EuiccSupportPixel/EuiccSupportPixel.apk";
          certificate = "PRESIGNED";
          privileged = true;
        };
      });
    })
    (mkIf (cfg.fi.enable && (config.deviceFamily == "crosshatch") && (config.androidVersion >= 10)) {
      # TODO: Hack. Make better
      source.dirs."robotnix/esimhack".contents = let
      in pkgs.runCommand "esim-hack" {} ''
        mkdir -p $out
        cp ${productPath}/priv-app/EuiccSupportPixel/esim-full-v0.img $out/
        cp ${productPath}/priv-app/EuiccSupportPixel/esim-v1.img $out/
      '';
      product.extraConfig = ''
        PRODUCT_COPY_FILES += robotnix/esimhack/esim-full-v0.img:$(TARGET_COPY_OUT_PRODUCT)/priv-app/EuiccSupportPixel/esim-full-v0.img
        PRODUCT_COPY_FILES += robotnix/esimhack/esim-v1.img:$(TARGET_COPY_OUT_PRODUCT)/priv-app/EuiccSupportPixel/esim-v1.img
      '';
    })
  ];
}

# EaselServicePrebuilt # pixel visual core
# crosshatch has: framswork/com.google.android.camera.experimental2018.jar
# https://github.com/opengapps/opengapps/blob/master/scripts/inc.buildtarget.sh has some useful information
