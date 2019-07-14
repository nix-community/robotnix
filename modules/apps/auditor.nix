{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.auditor;
in
{
  options = {
    apps.auditor = {
      enable = mkEnableOption "F-Droid";

      domain = mkOption {
        type = types.str;
        default = "attestation.app";
        description = "Domain running the AttestationServer (over https) for remote verification";
      };
    };
  };

  config = mkIf cfg.enable {
    apps.prebuilt.Auditor.apk = pkgs.callPackage ./auditor {
      inherit (cfg) domain;
      platformFingerprint = config.certs.platform.fingerprint; # Could parameterize this over config.apps.prebuilt.Auditor.certificate -- but who cares?
      deviceFamily = config.deviceFamily;
      avbFingerprint = config.certs.avb.fingerprint;
    };
  };
}
