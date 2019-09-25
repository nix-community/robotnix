{ config, pkgs, lib, ... }:

with lib;

let
  version = "0.2.8.17785";
in
{
  options = {
    microg.enable = mkEnableOption "microg";
  };

  config = mkIf config.microg.enable {
    source.dirs."frameworks/base".patches = [
      (pkgs.fetchpatch { # Better patch for microg that hardcodes the fake google signature and only allows microg apps to use it
        name = "microg.patch";
        url = "https://gitlab.com/calyxos/platform_frameworks_base/commit/dccce9d969f11c1739d19855ade9ccfbacf8ef76.patch";
        sha256 = "15c2i64dz4i0i5xv2cz51k08phlkhhg620b06n25bp2x88226m06";
      })
    ];
    resources."frameworks/base/packages/SettingsProvider".def_location_providers_allowed = mkIf (config.androidVersion != "10") "gps,network";

    # TODO: Preferably build this stuff ourself.
    # Used https://github.com/lineageos4microg/android_prebuilts_prebuiltapks as source for Android.mk options
    apps.prebuilt = {
      GmsCore = { 
        apk = pkgs.fetchurl { # Using calyox gmscore since it's newer than official prebuilt
          url = "https://gitlab.com/calyxos/platform_prebuilts_calyx/raw/2e51d79e521ab8ec458b22976aba2c75ee9fe2fe/microg/GmsCore/GmsCore.apk";
          sha256 = "0bc6j17pv3q3d9kixh3pdk56h9fjsxr90blgxr8andjhvz0vb5dp";
        };
        packageName = "com.google.android.gms";
        privileged = true;
        privappPermissions = [ "FAKE_PACKAGE_SIGNATURE" "INSTALL_LOCATION_PROVIDER" "CHANGE_DEVICE_IDLE_TEMP_WHITELIST" ];
      };

      GsfProxy.apk = pkgs.fetchurl {
        url = "https://github.com/microg/android_packages_apps_GsfProxy/releases/download/v0.1.0/GsfProxy.apk";
        sha256 = "14ln6i1qg435x223x3vndd608mra19d58yqqhhf6mw018cbip2c6";
      };

      FakeStore = {
        apk = pkgs.fetchurl {
          url = "https://github.com/microg/android_packages_apps_FakeStore/releases/download/v0.0.2/FakeStore.apk";
          sha256 = "0sc7wijslvji93h430fvy6gl5rnbrl7ynwbrai1895gplvjkigvz";
        };
        packageName = "com.android.vending";
        privileged = true;
        privappPermissions = [ "FAKE_PACKAGE_SIGNATURE" ];
      };
    };
  };
}
