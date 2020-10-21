{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.signing;
  keysToGenerate = [ "releasekey" "platform" "shared" "media" ]
                    ++ (optional (config.signing.avb.mode == "verity_only") "verity")
                    ++ (optionals (config.androidVersion >= 10) [ "networkstack" ])
                    ++ (optionals (config.androidVersion >= 11) [ "com.android.hotspot2.osulogin" "com.android.wifi.resources" ])
                    ++ (optional config.signing.apex.enable config.signing.apex.packageNames);
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
    verifyKeysScript = mkOption { type = types.path; internal = true; };
  };

  config = {
    signing.apex.enable = mkIf (config.androidVersion >= 10) (mkDefault true);
    signing.apex.packageNames = map (s: "com.android.${s}") (
      optionals (config.androidVersion == 10) [ "runtime.release" ]
      ++ optionals (config.androidVersion >= 10) [
        "conscrypt" "media" "media.swcodec" "resolv" "tzdata"
      ]
      ++ optionals (config.androidVersion >= 11) [
        "adbd" "art.release" "cellbroadcast" "extservices" "i18n"
        "ipsec" "mediaprovider" "neuralnetworks" "os.statsd" "runtime"
        "permission" "sdkext" "telephony" "tethering" "wifi"
      ]
    );

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
      ++ optionals ((config.androidVersion >= 11) && (config.flavor == "vanilla")) [
        "--key_mapping frameworks/base/packages/OsuLogin/certs/com.android.hotspot2.osulogin=$KEYSDIR/com.android.hotspot2.osulogin"
        "--key_mapping frameworks/opt/net/wifi/service/resources-certs/com.android.wifi.resources=$KEYSDIR/com.android.wifi.resources"
      ]
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
    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    in mkDefault (pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      KEYS=( ${toString keysToGenerate} )
      APEX_KEYS=( ${toString config.signing.apex.packageNames} )

      for key in "''${KEYS[@]}"; do
        if [[ ! -e "$key".pk8 ]]; then
          echo "Generating $key key"
          # make_key exits with unsuccessful code 1 instead of 0
          make_key "$key" "/CN=Robotnix ${config.device}/" && exit 1
        else
          echo "Skipping generating $key since it is already exists"
        fi
      done

      for key in "''${APEX_KEYS[@]}"; do
        if [[ ! -e "$key".pem ]]; then
          echo "Generating $key APEX AVB key"
          openssl genrsa -out "$key".pem 4096
          avbtool extract_public_key --key "$key".pem --output "$key".avbpubkey
        else
          echo "Skipping generating $key APEX key since it is already exists"
        fi
      done

      ${optionalString (config.signing.avb.mode == "verity_only") ''
      if [[ ! -e "verity_key.pub" ]]; then
          generate_verity_key -convert verity.x509.pem verity_key
      fi
      ''}


      ${optionalString (config.signing.avb.mode != "verity_only") ''
      if [[ ! -e "avb.pem" ]]; then
        # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
        echo "Generating Device AVB key"
        openssl genrsa -out avb.pem 2048
        avbtool extract_public_key --key avb.pem --output avb_pkmd.bin
      else
        echo "Skipping generating device AVB key since it is already exists"
      fi
      ''}
    '');

    # Check that all needed keys are available.
    verifyKeysScript = mkDefault (pkgs.writeScript "verify_keys.sh" ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      if [[ $# -ge 0 ]]; then
        cd "$1"
      fi

      KEYS=( ${toString keysToGenerate} )
      APEX_KEYS=( ${toString config.signing.apex.packageNames} )

      RETVAL=0

      for key in "''${KEYS[@]}"; do
        if [[ ! -e "$key".pk8 ]]; then
          echo "Missing $key key"
          RETVAL=1
        fi
      done

      for key in "''${APEX_KEYS[@]}"; do
        if [[ ! -e "$key".pem ]]; then
          echo "Missing $key APEX AVB key"
          RETVAL=1
        fi
      done

      ${optionalString (config.signing.avb.mode == "verity_only") ''
      if [[ ! -e "verity_key.pub" ]]; then
        echo "Missing verity_key.pub"
        RETVAL=1
      fi
      ''}

      ${optionalString (config.signing.avb.mode != "verity_only") ''
      if [[ ! -e "avb.pem" ]]; then
        echo "Missing Device AVB key"
        RETVAL=1
      fi
      ''}

      if [[ "$RETVAL" -ne 0 ]]; then
        echo  Certain keys were missing from KEYSDIR. Have you run generateKeysScript?
        echo  Additionally, some robotnix configuration options require that you re-run
        echo  generateKeysScript to create additional new keys.  This should not overwrite
        echo  existing keys.
      fi
      exit $RETVAL
    '');
  };
}
