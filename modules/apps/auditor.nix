{ config, pkgs, lib, ... }:

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
    apps.prebuilt.CustomAuditor = {
      # TODO: Generate this one with a script
      # Needs a special auditor key that is the same across devices.
      certificate = "auditor";
      apk = pkgs.callPackage ./auditor {
        inherit (cfg) domain;
        signatureFingerprint = config.build.fingerprints "auditor";
        deviceFamily = config.deviceFamily;
        avbFingerprint = config.build.fingerprints "avb";
      };
    };
  };
}
