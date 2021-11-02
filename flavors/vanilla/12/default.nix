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
  buildDateTime = mkDefault 1635822919;

  source.manifest.rev = mkDefault (
    if (elem config.deviceFamily [ "redfin" "barbet" ]) then "android-12.0.0_r10"
    else "android-12.0.0_r8"
  );
  apv.buildID = mkDefault (
    if (elem config.deviceFamily [ "redfin" "barbet" ]) then "SP1A.211105.003"
    else "SP1A.211105.002"
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

  # Fixes a crash when opening Battery Manager settings
  source.dirs."packages/apps/Settings".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/ProtonAOSP/android_packages_apps_Settings/commit/1aa49ec5017326ec6297e9ee067eb23647618494.patch";
      sha256 = "0nzr8c5chhlvd2zwvbk6a0cfxm6psrqbw94012igmhps4c04f2lx";
    })
  ];

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
  source.manifest.rev = "android-12.0.0_r1";
  apv.buildID = "SP1A.210812.015";
})
]))
