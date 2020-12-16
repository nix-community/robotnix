{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.signing;
  keysToGenerate = unique (
                    map (key: "${config.device}/${key}") [ "releasekey" "platform" "shared" "media" ]
                    ++ (optional (config.signing.avb.mode == "verity_only") "${config.device}/verity")
                    ++ (optionals (config.androidVersion >= 10) [ "${config.device}/networkstack" ])
                    ++ (optionals (config.androidVersion >= 11) [ "com.android.hotspot2.osulogin" "com.android.wifi.resources" ])
                    ++ (optional config.signing.apex.enable config.signing.apex.packageNames)
                    ++ (mapAttrsToList
                        (name: prebuilt: prebuilt.certificate)
                        (filterAttrs (name: prebuilt: prebuilt.certificate != "PRESIGNED") config.apps.prebuilt))
                    );

  # Cert fingerprints from default AOSP test-keys: build/make/tools/releasetools/testdata
  defaultDeviceCertFingerprints = {
    "releasekey" = "A40DA80A59D170CAA950CF15C18C454D47A39B26989D8B640ECD745BA71BF5DC";
    "platform" = "C8A2E9BCCF597C2FB6DC66BEE293FC13F2FC47EC77BC6B2B0D52C11F51192AB8";
    "media" = "465983F7791F2ABEB43EA2CBDC7F21A8260B72BC08A55C839FC1A43BC741A81E";
    "shared" = "28BBFE4A7B97E74681DC55C2FBB6CCB8D6C74963733F6AF6AE74D8C3A6E879FD";
    "verity" = "8AD127ABAE8285B582EA36745F220AB8FE397FFB3B068DF19CA22D122C7B3B86";
  };
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

    keyStorePath = mkOption {
      type = types.str;
      description = "Absolute path to generated keys for signing";
    };
  };

  config = {
    keyStorePath = mkIf (!config.signing.enable) (mkDefault (config.source.dirs."build/make".src + /target/product/security));

    build = let
      # TODO: Find a better way to do this?
      putInStore = path: if (hasPrefix builtins.storeDir path) then path else (/. + path);
    in {
      _keyPath = keyStorePath: name:
        let deviceCertificates = [ "releasekey" "platform" "media" "shared" "verity" ]; # Cert names used by AOSP
        in if builtins.elem name deviceCertificates
          then (if config.signing.enable
            then "${keyStorePath}/${config.device}/${name}"
            else "${config.source.dirs."build/make".src}/target/product/security/${replaceStrings ["releasekey"] ["testkey"] name}") # If not signing.enable, use test keys from AOSP
          else "${keyStorePath}/${name}";
      keyPath = name: config.build._keyPath config.keyStorePath name;
      sandboxKeyPath = name: (if config.signing.enable
        then config.build._keyPath "/keys" name
        else config.build.keyPath name);

      x509 = name: putInStore "${config.build.keyPath name}.x509.pem";
      fingerprints = name:
        if (name == "avb")
          then pkgs.robotnix.sha256Fingerprint (putInStore "${config.keyStorePath}/${config.device}/avb_pkmd.bin")
          else if (!config.signing.enable && elem name (attrNames defaultDeviceCertFingerprints))
            then defaultDeviceCertFingerprints.${name}
            else pkgs.robotnix.certFingerprint (config.build.x509 name); # IFD
    };

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
        "vndk.current" "vndk.v27" "vndk.v28" "vndk.v29"
      ]
    );

    signing.signTargetFilesArgs = let
      avbFlags = {
        verity_only = [
          "--replace_verity_public_key $KEYSDIR/${config.device}/verity_key.pub"
          "--replace_verity_private_key $KEYSDIR/${config.device}/verity"
          "--replace_verity_keyid $KEYSDIR/${config.device}/verity.x509.pem"
        ];
        vbmeta_simple = [
          "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained = [
          "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/${config.device}/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained_v2 = [
          "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/${config.device}/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
          "--avb_vbmeta_system_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_system_algorithm SHA256_RSA2048"
        ];
      }.${cfg.avb.mode}
      ++ optionals ((config.androidVersion >= 10) && (cfg.avb.mode != "verity_only")) [
        "--avb_system_other_key $KEYSDIR/${config.device}/avb.pem"
        "--avb_system_other_algorithm SHA256_RSA2048"
      ];
      keyMappings = {
         # Default key mappings from sign_target_files_apks.py
        "build/make/target/product/security/devkey" = "${config.device}/releasekey";
        "build/make/target/product/security/testkey" = "${config.device}/releasekey";
        "build/make/target/product/security/media" = "${config.device}/media";
        "build/make/target/product/security/shared" = "${config.device}/shared";
        "build/make/target/product/security/platform" = "${config.device}/platform";
      }
      // optionalAttrs (config.androidVersion >= 10) {
        "build/make/target/product/security/networkstack" = "${config.device}/networkstack";
      }
      // optionalAttrs (config.androidVersion >= 11) {
        "frameworks/base/packages/OsuLogin/certs/com.android.hotspot2.osulogin" = "com.android.hotspot2.osulogin";
        "frameworks/opt/net/wifi/service/resources-certs/com.android.wifi.resources" = "com.android.wifi.resources";
      }
      # App-specific keys
      // mapAttrs'
        (name: prebuilt: nameValuePair "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}" prebuilt.certificate)
        config.apps.prebuilt;
    in
      mapAttrsToList (from: to: "--key_mapping ${from}=$KEYSDIR/${to}") keyMappings
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

      if [[ "$#" -ne 1 ]]; then
        echo "Usage: $0 <keysdir>"
        echo "$#"
        exit 1
      fi

      mkdir -p "$1"
      cd "$1"

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      KEYS=( ${toString keysToGenerate} )
      APEX_KEYS=( ${lib.optionalString config.signing.apex.enable (toString config.signing.apex.packageNames)} )

      mkdir -p "${config.device}"

      for key in "''${KEYS[@]}"; do
        if [[ ! -e "$key".pk8 ]]; then
          echo "Generating $key key"
          # make_key exits with unsuccessful code 1 instead of 0
          make_key "$key" "/CN=Robotnix ''${key/\// }/" && exit 1
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
      if [[ ! -e "${config.device}/verity_key.pub" ]]; then
          generate_verity_key -convert ${config.device}/verity.x509.pem ${config.device}/verity_key
      fi
      ''}

      ${optionalString (config.signing.avb.mode != "verity_only") ''
      if [[ ! -e "${config.device}/avb.pem" ]]; then
        # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
        echo "Generating Device AVB key"
        openssl genrsa -out ${config.device}/avb.pem 2048
        avbtool extract_public_key --key ${config.device}/avb.pem --output ${config.device}/avb_pkmd.bin
      else
        echo "Skipping generating device AVB key since it is already exists"
      fi
      ''}
    '');

    # Check that all needed keys are available.
    # TODO: Remove code duplicated with generate_keys.sh
    verifyKeysScript = mkDefault (pkgs.writeScript "verify_keys.sh" ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      if [[ "$#" -ne 1 ]]; then
        echo "Usage: $0 <keysdir>"
        exit 1
      fi

      cd "$1"

      KEYS=( ${toString keysToGenerate} )
      APEX_KEYS=( ${lib.optionalString config.signing.apex.enable (toString config.signing.apex.packageNames)} )

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
      if [[ ! -e "${config.device}/verity_key.pub" ]]; then
        echo "Missing verity_key.pub"
        RETVAL=1
      fi
      ''}

      ${optionalString (config.signing.avb.mode != "verity_only") ''
      if [[ ! -e "${config.device}/avb.pem" ]]; then
        echo "Missing Device AVB key"
        RETVAL=1
      fi
      ''}

      if [[ "$RETVAL" -ne 0 ]]; then
        echo Certain keys were missing from KEYSDIR. Have you run generateKeysScript?
        echo Additionally, some robotnix configuration options require that you re-run
        echo generateKeysScript to create additional new keys.  This should not overwrite
        echo existing keys. If you have previously generated keys and see this message
        echo after recent changes in early December 2020, pleaseread the release notes
        echo in NEWS.md.
      fi
      exit $RETVAL
    '');
  };
}
