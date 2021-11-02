# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault;

  inherit (import ../supported-devices.nix { inherit lib config; })
    supportedDeviceFamilies phoneDeviceFamilies;
in
(mkIf (config.flavor == "vanilla" && config.androidVersion == 11) (mkMerge [
{
  buildDateTime = mkDefault 1633456788;

  source.manifest.rev = mkMerge [
    (mkIf (config.device != "barbet") (mkDefault "android-11.0.0_r46"))
    (mkIf (config.device == "barbet") (mkDefault "android-11.0.0_r48"))
  ];
  apv.buildID = mkMerge [
    (mkIf (config.device != "barbet") (mkDefault "RQ3A.211001.001"))
    (mkIf (config.device == "barbet") (mkDefault "RD2A.211001.002"))
  ];

  # Disable for now until we have it tested working
  kernel.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies &&
                        !(elem config.deviceFamily [ "redfin" "barbet"]))
                    (mkDefault true);

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

  # Clock app needs battery optimization exemption. Currently not in AOSP
  source.dirs."packages/apps/DeskClock".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_packages_apps_DeskClock/commit/0b21e707d7dca4c9c3e4ff030bef8fae3abed088.patch";
      sha256 = "0mzjzxyl8g2i520902bhc3ww3vbcwcx06m3zg033z0w6pw87apqc";
    })
  ];
}
(mkIf (elem config.device [ "taimen" "walleye" ]) {
  warnings = [ "taimen and walleye are no longer receiving monthly vendor security updates from Google" ];
  source.manifest.rev = "android-11.0.0_r25"; # More recent sources don't even include device/google/muskie
  apv.buildID = "RP1A.201005.004.A1";
})

]))
