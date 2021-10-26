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
  buildDateTime = mkDefault 1634663130;

  source.manifest.rev = mkDefault "android-12.0.0_r1";
  apv.buildID = mkDefault "SP1A.210812.015";

#  # Disable for now until we have it tested working
#  kernel.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies &&
#                        !(elem config.deviceFamily [ "redfin" "barbet"]))
#                    (mkDefault true);
  kernel.enable = false;

  # See also: https://github.com/GrapheneOS/os_issue_tracker/issues/325
  # List of biometric sensors on the device, in decreasing strength. Consumed by AuthService
  # when registering authenticators with BiometricService. Format must be ID:Modality:Strength,
  # where: IDs are unique per device, Modality as defined in BiometricAuthenticator.java,
  # and Strength as defined in Authenticators.java
  # TODO: This ought to show up in the vendor (not system or product) resource overlay
  resources."frameworks/base/core/res".config_biometric_sensors = {
    value = optional (elem config.deviceFamily phoneDeviceFamilies) (
              if (config.deviceFamily == "coral") then "0:8:15"
              else "0:2:15");
    type = "string-array";
  };

  # Temporary fix for crashes
  # https://github.com/GrapheneOS/platform_frameworks_base/commit/3c81f90076fbb49efb0bdd86826695ab88cd085f
  resources."frameworks/base/core/res".config_appsNotReportingCrashes = "com.android.statementservice";

  # Work around issue with checks for uses-library with apv output
  source.dirs."build/soong".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_build_soong/commit/2c00471cb204a9927570f48c92f058e3ae80a116.patch";
      sha256 = "110018jxzlflcm08lnvl8lik017xfq212y0qjd4rclxa1b652mnx";
    })
  ];
}
]))
