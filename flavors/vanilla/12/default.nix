# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault mkForce;

  inherit (import ../supported-devices.nix { inherit lib config; })
    supportedDeviceFamilies phoneDeviceFamilies;
in
(mkIf (config.flavor == "vanilla" && config.androidVersion == 12) (mkMerge [
{
  buildDateTime = mkDefault 1645396670;

  source.manifest.rev = mkDefault (
    if (config.deviceFamily == "raviole") then "android-12.1.0_r2"
    else "android-12.1.0_r1"
  );
  apv.buildID = mkDefault (
    if (config.deviceFamily == "raviole") then "SP2A.220305.013.A3"
    else "SP2A.220305.012"
  );

#  # Disable for now until we have it tested working
#  kernel.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies &&
#                        !(elem config.deviceFamily [ "redfin" "barbet"]))
#                    (mkDefault true);
  kernel.enable = false;

  resources."frameworks/base/core/res" = {
    # Temporary fix for crashes
    # https://github.com/GrapheneOS/platform_frameworks_base/commit/3c81f90076fbb49efb0bdd86826695ab88cd085f
    config_appsNotReportingCrashes = "com.android.statementservice";

    ### Additional usability improvements ###

    # Whether this device is supporting the microphone toggle
    config_supportsMicToggle = true;
    # Whether this device is supporting the camera toggle
    config_supportsCamToggle = true;
    # Default value for Settings.ASSIST_LONG_PRESS_HOME_ENABLED
    config_assistLongPressHomeEnabledDefault = false;
    # Default value for Settings.ASSIST_TOUCH_GESTURE_ENABLED
    config_assistTouchGestureEnabledDefault = false;
    # If this is true, long press on power button will be available from the non-interactive state
    config_supportLongPressPowerWhenNonInteractive = true;
    # Control the behavior when the user long presses the power button.
    #    0 - Nothing
    #    1 - Global actions menu
    #    2 - Power off (with confirmation)
    #    3 - Power off (without confirmation)
    #    4 - Go to voice assist
    #    5 - Go to assistant (Settings.Secure.ASSISTANT)
    config_longPressOnPowerBehavior = 1;
    #  Control the behavior when the user presses the power and volume up buttons together.
    #     0 - Nothing
    #     1 - Mute toggle
    #     2 - Global actions menu
    config_keyChordPowerVolumeUp = 1;
  };

  # Work around issue with checks for uses-library with apv output
  source.dirs."build/soong".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_build_soong/commit/2c00471cb204a9927570f48c92f058e3ae80a116.patch";
      sha256 = "110018jxzlflcm08lnvl8lik017xfq212y0qjd4rclxa1b652mnx";
    })
  ];
}
(mkIf (config.deviceFamily == "crosshatch") {
  warnings = [ "crosshatch and blueline are no longer receiving monthly vendor security updates from Google" ];
  source.manifest.rev = "android-12.0.0_r31";
  apv.buildID = "SP1A.210812.016.C1";
})
(mkIf (config.deviceFamily == "raviole") {
  source.dirs = {
    "device/google/gs101".patches = [
      ./device_google_gs101-workaround.patch
    ] ++ optional config.apv.enable ./device_google_gs101-vintf-manifest.patch;

    "frameworks/base".patches = [
      (pkgs.fetchpatch {
        name = "systemui-import-pixel-display-interfaces.patch";
        url = "https://github.com/ProtonAOSP/android_frameworks_base/commit/132bea5688fd7705a4c8a4ffe0a92a4c258f6b89.patch";
        sha256 = "sha256-sJA8zWRPQwo3sPIPPQQpJLdLmC9hOY96aHfl+NsPIN0=";
      })
      (pkgs.fetchpatch {
        name = "systemui-add-hbm-provider-for-udfps-n-pixel-devices.patch";
        url = "https://github.com/ProtonAOSP/android_frameworks_base/commit/155b137e1dfef173eeb391d5eea5ce3252ceaddc.patch";
        sha256 = "sha256-o03f5XZ+u+K1UrywG2Y28AjjK3ybaQE8mO0hVK9ypiQ=";
      })
      (pkgs.fetchpatch {
        name = "systemui-use-pixel-udfps-hbm-provider.patch";
        url = "https://github.com/ProtonAOSP/android_frameworks_base/commit/fa93eb6b0f87f8cb1f0a048285f55e4ca312e61f.patch";
        sha256 = "sha256-IKMlxUrdXYjtwU4ep7iwqjJtcXxBE4WDkNv4GfCnbw4=";
      })

      # In AOSP master
      (pkgs.fetchurl {
        name = "fix-concurrency-issue-with-batteryusagestats.patch";
        url = "https://github.com/aosp-mirror/platform_frameworks_base/commit/0856f76846e61ad058e1e9ec0759739812a00600.patch";
        sha256 = "sha256-of8dyOCicSVh64kLicuIk9av2K29YXLzUxeb6CI0NZo=";
      })
      (pkgs.fetchurl {
        name = "include-saved-battery-history-chunks-into-batteryusagestats-parcel.patch";
        url = "https://github.com/aosp-mirror/platform_frameworks_base/commit/c4b9de7d95fd2d6bd8072f16f0ac71d2b1773a1b.patch";
        sha256 = "sha256-ZIi96yF2qTgQ4iGTY86ppBmg4TeIRJ1qu7CSA5IPSnE=";
      })
    ];

    # Workaround for prebuilt apex package in vendor partition.
    # TODO: Replace with Nix-based apv alternative
    "robotnix/prebuilt/com.google.pixel.camera.hal" = {
      src = let
        Androidbp = pkgs.writeText "Android.bp" ''
          prebuilt_apex {
              name: "com.google.pixel.camera.hal",
              arch: {
                  arm64: {
                      src: "com.google.pixel.camera.hal.apex",
                  },
              },
              filename: "com.google.pixel.camera.hal.apex",
              vendor: true,
          }
        '';
      in pkgs.runCommand "com.google.pixel.camera.hal" {} ''
        mkdir -p $out

        cp ${Androidbp} $out/Android.bp
        cp ${config.build.apv.unpackedImg}/vendor/apex/com.google.pixel.camera.hal.apex $out/com.google.pixel.camera.hal.apex
      '';

      enable = config.apv.enable;
    };
  };

  vendor.additionalProductPackages = mkIf config.apv.enable [ "com.google.pixel.camera.hal" ];
  signing.apex.packageNames = mkIf config.apv.enable [ "com.google.pixel.camera.hal" ];

  # VINTF checks fail because apv doesn't do things correctly. TODO: Fix properly
  otaArgs = mkIf config.apv.enable [ "--skip_compatibility_check" ];

  nixpkgs.overlays = let
    owner = "zhaofengli";
    repo = "android-prepare-vendor";
    rev = "21b3650fe627d95ccce3237b8154a841d16ac265";
    sha256 = "1zyxc05lfiil1yzbivihfs9jafa3jkzyfha21bcgd07r482h2slf";
  in [ (self: super: {
    android-prepare-vendor = super.android-prepare-vendor.overrideAttrs (_: {
      src = pkgs.fetchFromGitHub {
        inherit owner repo rev sha256;
      };
      passthru.evalTimeSrc = builtins.fetchTarball {
        url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
        inherit sha256;
      };
    });
  }) ];
})
]))
