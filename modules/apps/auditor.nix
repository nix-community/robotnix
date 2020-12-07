{ config, pkgs, apks, lib, ... }:

with lib;
let
  cfg = config.apps.auditor;
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
      assertion = builtins.elem config.deviceFamily [ "taimen" "crosshatch" "sunfish" ];
      message = "Device ${config.deviceFamily} is currently unsupported.";
    } ];

    apps.prebuilt.Auditor = {
      # TODO: Generate this one with a script
      # TODO: Can sign with custom certs at the release stage instead
      # Needs a special auditor key that is the same across devices.
      certificate = "auditor";
      apk = apks.auditor.override {
        inherit (cfg) domain;
        signatureFingerprint = config.build.fingerprints "auditor";
        deviceFamily = config.deviceFamily;
        avbFingerprint = config.build.fingerprints "avb";
      };
    };
  };
}
