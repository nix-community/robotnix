{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.attestation-server;
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
{
  options.services.attestation-server = {
    enable = mkEnableOption "Hardware-based remote attestation service for monitoring the security of Android devices using the Auditor app";

    domain = mkOption {
      type = types.str;
    };

    listenHost = mkOption {
      default = "127.0.0.1";
      type = types.str;
    };

    port = mkOption {
      default = 8085;
      type = types.int;
    };

    signatureFingerprint = mkOption {
      type = types.str;
    };

    device = mkOption {
      default = "";
      type = types.str;
    };

    avbFingerprint = mkOption {
      default = "";
      type = types.str;
    };

    package = mkOption {
      default = pkgs.attestation-server.override {
        inherit (cfg) listenHost port domain signatureFingerprint device avbFingerprint;
      };
      type = types.path;
    };

    disableAccountCreation = mkOption {
      default = false;
      type = types.bool;
    };

    email = {
      username = mkOption {
        default = "";
        type = types.str;
      };

      passwordFile = mkOption {
        default = null;
        type = types.nullOr types.str;
      };

      host = mkOption {
        default = "";
        type = types.str;
      };

      port = mkOption {
        default = 587;
        type = types.int;
      };

      local = mkOption {
        default = false;
        type = types.bool;
      };
    };

    nginx.enable = mkOption {
      default = true;
      type = types.bool;
    };

    nginx.enableACME = mkOption {
      default = false;
      type = types.bool;
    };
  };

  config = mkIf cfg.enable {
    assertions = [ {
      assertion = builtins.elem cfg.device supportedDevices;
      message = "Device ${cfg.device} is currently unsupported for use with attestation server.";
    } ];

    systemd.services.attestation-server = {
      description = "Attestation Server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/AttestationServer";
        ExecStartPre = let
          inherit (cfg.email) username passwordFile host port local;
          # In SQLite readfile reads a file as a BLOB which is not very useful.
          # However, we can use TRIM to convert it to a string and we have to
          # truncate the trailing newline (\n = char(10)) anyway.
          values = concatStringsSep ", " [
            "('emailUsername', '${username}')"
            "('emailPassword', TRIM(readfile('%S/attestation/emailPassword'), char(10)))"
            "('emailHost', '${host}')"
            "('emailPort', '${toString port}')"
            "('emailLocal', '${if local then "1" else "0"}')"
          ];
        in optionals (passwordFile != null) [
          # Note the leading + on the first command. The passwordFile could be
          # anywhere in the file system, so it has to be copied as root and
          # permissions fixed to be accessible by the service.
          "+${pkgs.coreutils}/bin/install -m 0600 -o %N -g %N ${passwordFile} %S/attestation/emailPassword"
          ''${pkgs.sqlite}/bin/sqlite3 %S/attestation/attestation.db "INSERT OR REPLACE INTO Configuration VALUES ${values}"''
          "${pkgs.coreutils}/bin/rm -f %S/attestation/emailPassword"
        ];

        # When sending TERM, e.g. for restart, AttestationServer fails with
        # this exit code.
        SuccessExitStatus = [ 143 ];

        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;

        NoNewPrivileges = true;
        PrivateDevices = true;
        StateDirectory = "attestation";
        WorkingDirectory = "%S/attestation";
      };
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      virtualHosts."${config.services.attestation-server.domain}" = recursiveUpdate {
        locations."/".root = cfg.package.static;
        locations."/api/".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/api/";
        locations."/challenge".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/challenge";
        locations."/verify".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/verify";
        forceSSL = true;
        enableACME = cfg.nginx.enableACME;
      } (optionalAttrs cfg.disableAccountCreation {
        locations."/api/create_account".return = "403";
      });
    };
  };
}
