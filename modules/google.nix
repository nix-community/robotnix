# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.google;

  # TODO: Use repairedImg from android-prepare-vendor
  systemPath = "${unpackedImg}/system/system";

  # Android 10 separates product specific apps/config, but its still under system in marlin
  productPath = if (config.androidVersion >= 10)
    then "${unpackedImg}/${optionalString (config.deviceFamily == "marlin") "system/system/"}product"
    else systemPath;
  systemExtPath = if (config.androidVersion >= 11)
    then "${unpackedImg}/system_ext"
    else productPath;

  unpackedImg = if config.apv.enable
    then config.build.apv.unpackedImg
    else (import ../default.nix { # If apv is not enabled--say for generic/emulator targets, use the vendor files from crosshatch
      configuration = {
        device = "crosshatch";
        flavor = "vanilla";
        inherit (config) androidVersion;
      };
    }).config.build.apv.unpackedImg;
in
{
  # TODO: Add other google stuff. Ensure that either google play services or microg is enabled if these are.
  options = {
    google = {
      base.enable = mkEnableOption "Base Google OEM files (experimental)";
      dialer.enable = mkEnableOption "Google Dialer (experimental)";
      fi.enable = mkEnableOption "Google Fi (experimental)";
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
      } // (optionalAttrs (config.androidVersion == 10) {
        "permissions/privapp-permissions-google-ps.xml".source = "${productPath}/etc/permissions/privapp-permissions-google-ps.xml";
      }) // (optionalAttrs (config.androidVersion >= 10) {
        "permissions/privapp-permissions-google-p.xml".source = "${productPath}/etc/permissions/privapp-permissions-google-p.xml";
      }) // (optionalAttrs (config.androidVersion >= 11) {
        "permissions/privapp-permissions-google-se.xml".source = "${systemExtPath}/etc/permissions/privapp-permissions-google-se.xml";
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
        apk = pkgs.robotnix.verifyApk {
          apk = "${productPath}/priv-app/GoogleDialer/GoogleDialer.apk";
          sha256 = "e2d049f3a01192f620b1240615fa8c13badc553c22bc6fddfca45c84d8fc545d";
        };
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
        Tycho = { # Google Fi app
          apk = pkgs.robotnix.verifyApk {
            apk = "${productPath}/app/Tycho/Tycho.apk";
            sha256 = "4c36af4a5bdad97c1f3d8b283416d244496c2ac5eafe8226079ef6f676fd1859";
          };
          certificate = "PRESIGNED";
        };
        GCS = { # Google Connectivity Services (does wifi VPN at least)
          apk = pkgs.robotnix.verifyApk {
            apk = "${productPath}/priv-app/GCS/GCS.apk";
            sha256 = "8efed9b84a6320eafde625cea7bb6bae0e320473d0e3c04fb0cd43b779078e1d";
          };
          certificate = "PRESIGNED";
          privileged = true;
        };
#### Disabling for now, since calls aren't working ####
#        CarrierServices = {
#          apk = pkgs.robotnix.verifyApk {
#            apk = "${productPath}/priv-app/CarrierServices/CarrierServices.apk"; # Google Carrier Services. com.google.android.ims (needed for wifi calls)
#            sha256 = "c25d5afacb6783109d6136d79353fad4f6541c3545d25228a18703d043ca783f";
#          };
#          certificate = "PRESIGNED";
#          privileged = true;
#        };
        CarrierSettings = { # com.google.android.carrier
          apk = pkgs.robotnix.verifyApk {
            apk = "${productPath}/priv-app/CarrierSettings/CarrierSettings.apk";
            sha256 = "383d1e1b525ec6fb8204c5bf9b8390d37fd157e78b8b7212d61487b178066d20";
          };
          certificate = "PRESIGNED";
          privileged = true;
        };
        CarrierSetup = { # com.google.android.carriersetup
          apk = "${systemExtPath}/priv-app/CarrierSetup/CarrierSetup.apk"; # Uses device-specific keys
          certificate = "PRESIGNED";
          privileged = true;
        };
      } // (optionalAttrs (config.deviceFamily == "crosshatch") { # TODO: Generalize to other devices with esim
        EuiccGoogle = {
          apk = pkgs.robotnix.verifyApk {
            apk = "${productPath}/priv-app/EuiccGoogle/EuiccGoogle.apk";
            sha256 = "7e26b6d5802a16799448ad635868f0345d6730310634684c0ae44e7e9f7ea764";
          };
          certificate = "PRESIGNED";
          privileged = true;
        };
      }) // (optionalAttrs ((config.deviceFamily == "crosshatch") && (config.androidVersion >= 10)) {
        EuiccSupportPixel = {
          apk = pkgs.robotnix.verifyApk {
            apk = "${productPath}/priv-app/EuiccSupportPixel/EuiccSupportPixel.apk";
            sha256 = "e0afeca77af15aee48a25ead314c576f8f274682a8fba3365610878f7c1ddb6b";
          };
          certificate = "PRESIGNED";
          privileged = true;
        };
      });
      # Protobufs used in CarrierSettings (TODO find a better way to manage this)
      etc = listToAttrs (map (n: nameValuePair "CarrierSettings/${n}.pb" { source = "${productPath}/etc/CarrierSettings/${n}.pb"; }) [
        "airtel_in" "att5g_us" "att_us" "bell_ca" "bluegrass_us" "boost_us"
        "bouygues_fr" "btb_gb" "btc_gb" "carrier_list" "cellcom_us" "cht_tw"
        "cricket5g_us" "cricket_us" "cspire_us" "default" "docomo_jp" "ee_gb"
        "eplus_de" "fet_tw" "fido_ca" "firstnetpacific_us" "firstnet_us"
        "fi_us" "fizz_ca" "freedommobile_ca" "h3_at" "h3_gb" "h3_se" "idea_in"
        "idmobile_gb" "kddi_jp" "kddimvno_jp" "koodo_ca" "luckymobile_ca"
        "o2_de" "o2postpaid_gb" "o2prepaid_de" "o2prepaid_gb" "optus_au"
        "orange_es" "orange_fr" "others" "pcmobilebell_ca" "rakuten_jp"
        "rjio_in" "rogers_ca" "sfr_fr" "shaw_ca" "singtel_sg" "softbank_jp"
        "solomobile_ca" "spectrum_us" "sprintprepaid_us" "sprint_us"
        "sprintwholesale_us" "starhub_sg" "swisscom_ch" "swisscom_li" "tdc_dk"
        "tele2_se" "telekom_de" "telenor_dk" "telenor_no" "telia_no" "telia_se"
        "telstra_au" "telus_ca" "three_dk" "tim_it" "tmobile_nl" "tmobile_us"
        "tracfonetmo_us" "tracfoneverizon_us" "twm_tw" "uscc_us" "verizon_us"
        "videotron_ca" "virgin_ca" "virgin_us" "visible_us" "vodafone_au"
        "vodafone_de" "vodafone_es" "vodafone_gb" "vodafone_in" "vodafone_it"
        "vodafone_nl" "vodafone_tr" "xfinity_us"
      ]);
    })
    (mkIf (cfg.fi.enable && (config.deviceFamily == "crosshatch") && (config.androidVersion >= 10)) {
      # TODO: Hack. Make better
      source.dirs."robotnix/esimhack".src = let
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
