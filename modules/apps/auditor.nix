{ config, pkgs, apks, lib, ... }:

with lib;
let
  cfg = config.apps.auditor;
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
{
  options = {
    apps.auditor = {
      enable = mkEnableOption "Auditor";

      domain = mkOption {
        type = types.str;
        default = "attestation.app";
        description = "Domain running the AttestationServer (over https) for remote verification";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [ {
      assertion = builtins.elem config.device supportedDevices;
      message = "Device ${config.device} is currently unsupported for use with auditor app.";
    } ];

    apps.prebuilt.Auditor = {
      apk = apks.auditor.override {
        inherit (cfg) domain;
        inherit (config) device;
        signatureFingerprint = config.apps.prebuilt."Auditor".fingerprint;
        avbFingerprint = config.build.fingerprints "avb";
      };
    };
  };
}
