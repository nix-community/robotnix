# SPDX-FileCopyrightText: 2026 cyclopentane and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.signing;
  pivLabels = {
    "9a" = "PIV Authentication";
    "9c" = "Digital Signature";
    "9d" = "Key Management";
    "9e" = "Card Authentication";
    "82" = "Retired Key 1";
    "83" = "Retired Key 2";
    "84" = "Retired Key 3";
    "85" = "Retired Key 4";
    "86" = "Retired Key 5";
    "87" = "Retired Key 6";
    "88" = "Retired Key 7";
    "89" = "Retired Key 8";
    "8a" = "Retired Key 9";
    "8b" = "Retired Key 10";
    "8c" = "Retired Key 11";
    "8d" = "Retired Key 12";
    "8e" = "Retired Key 13";
    "8f" = "Retired Key 14";
    "90" = "Retired Key 15";
    "91" = "Retired Key 16";
    "92" = "Retired Key 17";
    "93" = "Retired Key 18";
    "94" = "Retired Key 19";
    "95" = "Retired Key 20";
    "f9" = "PIV Attestation";
  };
  opensslCnf = pkgs.writeText "openssl.cnf" ''
    [openssl_init]
    providers = provider_sect

    [provider_sect]
    default = default_sect
    pkcs11 = pkcs11_sect

    [default_sect]
    activate = 1

    [pkcs11_sect]
    identity = pkcs11prov
    module = pkcs11prov.so
    activate = 1
  '';
  opensslEnvVars = ''
    export PATH=${
      lib.makeBinPath (
        with pkgs;
        [
          coreutils
          openssl
          urlencode
        ]
      )
    }
    export OPENSSL_CONF=${opensslCnf}
    export OPENSSL_MODULES=${pkgs.libp11}/lib/ossl-module
    export PKCS11_MODULE_PATH=${pkgs.yubico-piv-tool}/lib/libykcs11.so

    PKCS11_URI="pkcs11:object=$(urlencode "$KEY");type=private"
  '';
  otaPayloadSigner = pkgs.writeShellScript "ota-payload-signer" ''
    set -euo pipefail
    # it would be overkill to write a full-blown arg parser here, so
    # we only check for the exact arg order that
    # payload_signer.py:SignHashFile invokes the payload_signer script with.

    if [ $# -ne 4 || "$1" != "-in" || "$3" != "-out" ]; then
      echo "usage: $0 -in <infile> -out <outfile>"
      exit 1
    fi
    INFILE="$2"
    OUTFILE="$4"

    ${opensslEnvVars}

    openssl pkeyutl -provider default -provider pkcs11prov -passin file:$PIN_FILE -inkey "$PKCS11_URI" -in "$INFILE" -out "$OUTFILE"
  '';
in
{
  options.signing.pkcs11 = {
    enable = lib.mkEnableOption "PKCS#11 signing";

    module = lib.mkOption {
      type = lib.types.pathInStore;
      description = ''
        The PKCS#11 shared library to use for signing.
      '';
      example = "\${pkgs.yubico-piv-tool}/lib/libykcs11.so";
    };

    privateKeyLabels = lib.mkOption {
      type = with lib.types; attrsOf str;
      description = ''
        The mapping of robotnix key names (e.g. `tegu/releasekey`) to
        PKCS#11 private key labels (CKA_LABEL attribute).
      '';
    };

    certificateLabels = lib.mkOption {
      type = with lib.types; attrsOf str;
      description = ''
        The mapping of robotnix key names (e.g. `tegu/releasekey`) to
        PKCS#11 certificate labels (CKA_LABEL attribute).
      '';
    };

    presets = {
      yubikey-piv = {
        enable = lib.mkEnableOption "the YubiKey PIV PKCS#11 signing preset.";
        slotMap = lib.mkOption {
          type = with lib.types; attrsOf str;
          description = ''
            The YubiKey PIV slots to use for the individual keys.
          '';
          default = {
            "${config.device}/releasekey" = "82";
            "${config.device}/media" = "83";
            "${config.device}/shared" = "84";
            "${config.device}/platform" = "85";
            "${config.device}/sdk_sandbox" = "86";
            "${config.device}/nfc" = "87";
            "${config.device}/networkstack" = "88";
            "${config.device}/avb" = "89";
            # grapheneos gmscompat_lib: 8a
            # grapheneos bluetooth:     8b
          };
          defaultText = ''
            {
              "''${config.device}/releasekey" = "82";
              "''${config.device}/media" = "83";
              "''${config.device}/shared" = "84";
              "''${config.device}/platform" = "85";
              "''${config.device}/sdk_sandbox" = "86";
              "''${config.device}/nfc" = "87";
              "''${config.device}/networkstack" = "88";
              "''${config.device}/avb" = "89";
            }
          '';
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.pkcs11.enable {
      assertions = [
        {
          assertion = lib.versionAtLeast config.stateVersion "3";
          message = ''PKCS#11 signing requires a stateVersion of at least "3".'';
        }
      ];

      signing = {
        extraFlags =
          let
            sunPKCS11Config = pkgs.writeText "pkcs11.cfg" ''
              name = Robotnix_PKCS11
              library = ${cfg.pkcs11.module}
            '';
          in
          [
            ''--extra_signapk_args "-providerClass sun.security.pkcs11.SunPKCS11 -providerArg ${sunPKCS11Config} -loadPrivateKeysFromkeyStore PKCS11 -keyStorePinFile $PIN_FILE"''
          ]
          ++ (lib.mapAttrsToList (from: to: "--public_key_mapping ${from}=$KEYSDIR/${to}") cfg.keyMappings);
        avbFlags =
          let
            avbSigningHelper = pkgs.writeShellScript "avb-signing-helper" ''
              set -euo pipefail
              ALGORITHM="$1"
              KEY="$2"
              ${opensslEnvVars}
              openssl rsautl -provider default -provider pkcs11prov -passin file:$PIN_FILE -inkey "$PKCS11_URI" -raw
            '';
          in
          [
            ''--avb_vbmeta_extra_args "--signing_helper ${avbSigningHelper}"''
            ''--avb_system_extra_args "--signing_helper ${avbSigningHelper}"''
            ''--avb_system_other_extra_args "--signing_helper ${avbSigningHelper}"''
            ''--avb_vbmeta_system_extra_args "--signing_helper ${avbSigningHelper}"''
            ''--avb_system_other_pkmd "$KEYSDIR/${cfg.avb.key}_pkmd.bin"''
            ''--apex_com.android.virt.apex_pkmd "$KEYSDIR/${cfg.avb.key}_pkmd.bin"''
          ];

        otaFlags = [
          "--payload_signer ${otaPayloadSigner}"
        ];
      };
    })
    (lib.mkIf cfg.pkcs11.presets.yubikey-piv.enable {
      signing.pkcs11 = {
        module = "${pkgs.yubico-piv-tool}/lib/libykcs11.so";
        privateKeyLabels = lib.mapAttrs (
          _: slot: "Private key for ${pivLabels.${slot}}"
        ) cfg.pkcs11.presets.yubikey-piv.slotMap;
        certificateLabels = lib.mapAttrs (
          _: slot: "X.509 Certificate for ${pivLabels.${slot}}"
        ) cfg.pkcs11.presets.yubikey-piv.slotMap;
      };
    })
  ];
}
