{ config, pkgs, lib, ... }:

with lib;

let
  version = {
    part1 = "0.2.16";
    part2 = "204713";
    part3 = "032";
  };
  verifyApk = apk: pkgs.robotnix.verifyApk {
    inherit apk;
    sha256 = "9bd06727e62796c0130eb6dab39b73157451582cbd138e86c468acc395d14165"; # O=NOGAPPS Project, C=DE
  };
in
{
  options = {
    microg.enable = mkEnableOption "microg";
  };

  config = mkIf config.microg.enable {
    # Uses better patch for microg that hardcodes the fake google signature and only allows microg apps to use it
    source.dirs."frameworks/base".patches =
      if (config.androidVersion >= 11)
      then [ ./microg-android11.patch ]
      else [ (pkgs.fetchpatch {
        name = "microg.patch";
        url = "https://gitlab.com/calyxos/platform_frameworks_base/commit/dccce9d969f11c1739d19855ade9ccfbacf8ef76.patch";
        sha256 = "15c2i64dz4i0i5xv2cz51k08phlkhhg620b06n25bp2x88226m06";
      }) ];

    resources."frameworks/base/packages/SettingsProvider".def_location_providers_allowed = mkIf (config.androidVersion == 9) "gps,network";

    # TODO: Preferably build this stuff ourself.
    # Used https://github.com/lineageos4microg/android_prebuilts_prebuiltapks as source for Android.mk options
    apps.prebuilt = {
      GmsCore = { 
        apk = verifyApk (pkgs.fetchurl {
          url = "https://github.com/microg/GmsCore/releases/download/v${version.part1}.${version.part2}/com.google.android.gms-${version.part2}${version.part3}.apk";
          sha256 = "0mx9cchdba7zz57aq6pwffbw54vy06xcv7gqw7v1kz02v9sgmspy";
        });
        packageName = "com.google.android.gms";
        privileged = true;
        privappPermissions = [ "FAKE_PACKAGE_SIGNATURE" "INSTALL_LOCATION_PROVIDER" "CHANGE_DEVICE_IDLE_TEMP_WHITELIST" "UPDATE_APP_OPS_STATS" ];
        defaultPermissions = [ "FAKE_PACKAGE_SIGNATURE" ];
        allowInPowerSave = true;
        certificate = "microg";
      };

      GsfProxy = {
        apk = verifyApk (pkgs.fetchurl {
          url = "https://github.com/microg/android_packages_apps_GsfProxy/releases/download/v0.1.0/GsfProxy.apk";
          sha256 = "14ln6i1qg435x223x3vndd608mra19d58yqqhhf6mw018cbip2c6";
        });
        certificate = "microg";
      };

      FakeStore = {
        apk = verifyApk (pkgs.fetchurl {
          url = "https://github.com/microg/android_packages_apps_FakeStore/releases/download/v0.1.0/FakeStore-v0.1.0.apk";
          sha256 = "1kp5v4qajp4cdx8pxw6j4776bcwc9f8jgfpiyllpk1kbhq92w1ci";
        });
        packageName = "com.android.vending";
        privileged = true;
        privappPermissions = [ "FAKE_PACKAGE_SIGNATURE" ];
        defaultPermissions = [ "FAKE_PACKAGE_SIGNATURE" ];
        certificate = "microg";
      };
    };
  };
}
