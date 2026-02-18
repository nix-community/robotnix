# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  apks,
  lib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  cfg = config.apps.auditor;
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
{
  options = {
    apps.auditor = {
      enable = mkEnableOption "Auditor";

      domain = mkOption {
        type = types.str;
        description = "Domain running the AttestationServer (over HTTPS) for remote verification";
        example = "attestation.example.com";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.elem config.device supportedDevices;
        message = "Device ${config.device} is currently unsupported for use with Auditor app.";
      }
    ];

    apps.prebuilt.Auditor = {
      apk = apks.auditor.override {
        inherit (cfg) domain;
        inherit (config) device;
      };
    };
  };
}
