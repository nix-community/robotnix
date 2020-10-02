{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.signing;
in
{
  options = {
    signing = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Whether to sign build using user-provided keys. Otherwise, build will be signed using insecure test-keys.";
      };

      signTargetFilesArgs = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
      };

      avb = {
        enable = mkEnableOption "AVB signing";

        # TODO: Refactor
        mode = mkOption {
          type = types.strMatching "(verity_only|vbmeta_simple|vbmeta_chained|vbmeta_chained_v2)";
          default  = "vbmeta_chained";
        };
      };

      apex = {
        enable = mkEnableOption "APEX signing";

        packageNames = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "APEX packages which need to be signed";
        };
      };
    };

    generateKeysScript = mkOption { type = types.path; internal = true; };
  };

  config = {
    signing.signTargetFilesArgs = let
      avbFlags = {
        verity_only = [
          "--replace_verity_public_key $KEYSDIR/verity_key.pub"
          "--replace_verity_private_key $KEYSDIR/verity"
          "--replace_verity_keyid $KEYSDIR/verity.x509.pem"
        ];
        vbmeta_simple = [
          "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained = [
          "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained_v2 = [
          "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
          "--avb_vbmeta_system_key $KEYSDIR/avb.pem" "--avb_vbmeta_system_algorithm SHA256_RSA2048"
        ];
      }.${cfg.avb.mode}
      ++ optionals ((config.androidVersion >= 10) && (cfg.avb.mode != "verity_only")) [
        "--avb_system_other_key $KEYSDIR/avb.pem"
        "--avb_system_other_algorithm SHA256_RSA2048"
      ];
    in
      optional (config.androidVersion >= 10) "--key_mapping build/target/product/security/networkstack=$KEYSDIR/networkstack"
      ++ optionals cfg.avb.enable avbFlags
      ++ optionals cfg.apex.enable (map (k: "--extra_apks ${k}.apex=$KEYSDIR/${k} --extra_apex_payload_key ${k}.apex=$KEYSDIR/${k}.pem") cfg.apex.packageNames);

    generateKeysScript = let
      # Get a bunch of utilities to generate keys
      keyTools = pkgs.runCommandCC "android-key-tools" { buildInputs = [ pkgs.python ]; } ''
        mkdir -p $out/bin

        cp ${config.source.dirs."development".src}/tools/make_key $out/bin/make_key
        substituteInPlace $out/bin/make_key --replace openssl ${getBin pkgs.openssl}/bin/openssl

        cc -o $out/bin/generate_verity_key \
          ${config.source.dirs."system/extras".src}/verity/generate_verity_key.c \
          ${config.source.dirs."system/core".src}/libcrypto_utils/android_pubkey.c \
          -I ${config.source.dirs."system/core".src}/libcrypto_utils/include/ \
          -I ${pkgs.boringssl}/include ${pkgs.boringssl}/lib/libssl.a ${pkgs.boringssl}/lib/libcrypto.a -lpthread

        cp ${config.source.dirs."external/avb".src}/avbtool $out/bin/avbtool

        patchShebangs $out/bin
      '';

      keysToGenerate = [ "releasekey" "platform" "shared" "media" ]
                        ++ (optional (config.signing.avb.mode == "verity_only") "verity")
                        ++ (optionals (config.androidVersion >= 10) [ "networkstack" ])
                        ++ (optional config.signing.apex.enable config.signing.apex.packageNames);
    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    in mkDefault (pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      for key in ${toString keysToGenerate}; do
        # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
        ! make_key "$key" "$1"
      done

      ${optionalString (config.signing.avb.mode == "verity_only") "generate_verity_key -convert verity.x509.pem verity_key"}

      # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
      ${optionalString (config.signing.avb.mode != "verity_only") ''
        openssl genrsa -out avb.pem 2048
        avbtool extract_public_key --key avb.pem --output avb_pkmd.bin
      ''}

      ${concatMapStringsSep "\n" (k: ''
        openssl genrsa -out ${k}.pem 4096
        avbtool extract_public_key --key ${k}.pem --output ${k}.avbpubkey
      '') config.signing.apex.packageNames}
    '');
  };
}
