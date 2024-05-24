# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkDefault mkEnableOption mkMerge;

  versions = {
    release = "v0.3.5.240913"; # The GH release name and git tag
    GmsCore = {
      buildNumber = "240913010"; # The build number of the artefact in the release
      hash = "sha256-qvR54f+TLV3Yz1RbdsCFf3E4GW87r5lMD6lCmq4qYio=";
    };
    FakeStore = {
      buildNumber = "84022610"; # The build number of the artefact in the release
      hash = "sha256-iDaCFnp184vowFZN/9jJzFIYUdY//Uoo2KXp4s0d3Yo=";
    };
  };

  verifyApk = apk: pkgs.robotnix.verifyApk {
    inherit apk;
    sha256 = "9bd06727e62796c0130eb6dab39b73157451582cbd138e86c468acc395d14165"; # O=NOGAPPS Project, C=DE
  };
in
{
  options = {
    microg.enable = mkEnableOption "MicroG";

    # TODO: Add support for spoofing device profiles. See: https://github.com/microg/GmsCore/releases/tag/v0.2.23.214816
  };

  config = mkIf config.microg.enable {
    source.dirs = mkMerge [
      (mkIf (config.androidVersion == 12 || config.androidVersion == 13) {
        # From: https://github.com/microg/GmsCore/pull/1586
        "frameworks/base".patches = lib.optionals (config.androidVersion == 12) [
          (pkgs.fetchpatch {
            name = "microg-12.patch";
            url = "https://github.com/ProtonAOSP/android_frameworks_base/commit/0deff13d05e451fbe3803f66be73853237c6729c.patch";
            sha256 = "0gcwb5811wv5fz4vjavljcbw9m5rplrd3fc7d51w3r4w4vv0yl4c";
          })
        ] ++ lib.optionals (config.androidVersion >= 13) [
          (pkgs.fetchpatch {
            name = "microg-12.patch";
            url = "https://github.com/AOSP-XIII/frameworks_base/commit/fdc0204576d61b5a90838ae5b407535e5db125e6.patch";
            sha256 = "09xsw4dizjxjr8siaaw6lw6zwbcjrvxz574hz6251p4j7v4y2ddr";
          })
        ];
        "packages/modules/Permission".patches =
          lib.optional (config.flavor == "grapheneos") (pkgs.fetchpatch {
            name = "fake-package-signature.patch";
            url = "https://github.com/ProtonAOSP/android_packages_modules_Permission/commit/de7846184379955956021b6e7b1730b24c8f4802.patch";
            sha256 = "1644nh8fnf5nxawdfqixxsf786s1fhx6jp42awjiii98nkc8pg6d";
          })
          ++ lib.optional (config.flavor != "grapheneos") ./microg-android12-permission.patch;
      })
      (mkIf (config.androidVersion == 11) {
        # Uses better patch for microg that hardcodes the fake google signature and only allows microg apps to use it
        "frameworks/base".patches = [ ./microg-android11.patch ];
      })
      (mkIf (config.androidVersion == 10) {
        "frameworks/base".patches = [
          (pkgs.fetchpatch {
            name = "microg.patch";
            url = "https://gitlab.com/calyxos/platform_frameworks_base/commit/dccce9d969f11c1739d19855ade9ccfbacf8ef76.patch";
            sha256 = "15c2i64dz4i0i5xv2cz51k08phlkhhg620b06n25bp2x88226m06";
          })
        ];
      })
    ];

    resources."frameworks/base/packages/SettingsProvider".def_location_providers_allowed = mkIf (config.androidVersion == 9) (mkDefault "gps,network");

    # Using cloud messaging, so enabling: https://source.android.com/devices/tech/power/platform_mgmt#integrate-doze
    resources."frameworks/base/core/res".config_enableAutoPowerModes = mkDefault true;

    # TODO: Preferably build this stuff ourself.
    # Used https://github.com/lineageos4microg/android_prebuilts_prebuiltapks as source for Android.mk options
    apps.prebuilt = let
      # Currently LOS only allows µG to be signed with the upstream keys and
      # that's the only supported method to get signature spoofing.
      #
      # FIXME patch that out and make it accept the signing key instead
      certificate = if config.flavor == "lineageos" && config.androidVersion >= 13 then "PRESIGNED" else "microg";
    in {
      GmsCore = {
        apk = verifyApk (pkgs.fetchurl {
          url = "https://github.com/microg/GmsCore/releases/download/${versions.release}/com.google.android.gms-${versions.GmsCore.buildNumber}.apk";
          inherit (versions.GmsCore) hash;
        });
        packageName = "com.google.android.gms";
        privileged = true;
        privappPermissions = [
          "FAKE_PACKAGE_SIGNATURE"
          "INSTALL_LOCATION_PROVIDER"
          "CHANGE_DEVICE_IDLE_TEMP_WHITELIST"
          "UPDATE_APP_OPS_STATS"
          "MANAGE_USB"

          # New with v0.2.28.231657
          "LOCATION_HARDWARE"
          "MODIFY_PHONE_STATE"
          "NETWORK_SCAN"
          "UPDATE_DEVICE_STATS"
          "WATCH_APPOPS"

          # New with v0.2.29.233013
          "RECEIVE_SMS"

          # New with v0.3.1.240913
          "START_ACTIVITIES_FROM_BACKGROUND"
        ];
        defaultPermissions = [ "FAKE_PACKAGE_SIGNATURE" ];
        usesLibraries = [ "com.android.location.provider" ];
        usesOptionalLibraries = [ "org.apache.http.legacy" "androidx.window.extensions" "androidx.window.sidecar" ];
        allowInPowerSave = true;
        inherit certificate;
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
          url = "https://github.com/microg/GmsCore/releases/download/${versions.release}/com.android.vending-${versions.FakeStore.buildNumber}.apk";
          inherit (versions.FakeStore) hash;
        });
        packageName = "com.android.vending";
        privileged = true;
        privappPermissions = [
          "FAKE_PACKAGE_SIGNATURE"
          "CHECK_LICENSE"
        ];
        defaultPermissions = [ "FAKE_PACKAGE_SIGNATURE" ];
        usesOptionalLibraries = [ "androidx.window.extensions" "androidx.window.sidecar" ];
        inherit certificate;
      };
    };
  };
}
