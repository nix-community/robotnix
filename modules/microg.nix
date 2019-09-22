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
    source.patches = [ ./microg-sigspoof.patch ];
    resources."frameworks/base/packages/SettingsProvider".def_location_providers_allowed = mkIf (config.androidVersion != "10") "gps,network"; # Lots of stuff is currently broken with microg and android 10 anyway

    # Preferably build this stuff ourself.
    # Used https://github.com/lineageos4microg/android_prebuilts_prebuiltapks as source for Android.mk options
    apps.prebuilt = {
      GmsCore = { 
        apk = pkgs.fetchurl {
          url = "https://github.com/microg/android_packages_apps_GmsCore/releases/download/v${version}/GmsCore-v${version}-mapbox.apk";
          sha256 = "0hripz5ifmk0abkcd48qdh7442b6ycbyi3dwqj6a2f773j6xgg2d";
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
