# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkMerge mkOption mkEnableOption mkDefault mkOptionDefault mkRenamedOptionModule mkSubModule types;

  cfg = config.signing;

  # TODO: Find a better way to do this?
  putInStore = path: path;

  keysToGenerate = lib.unique (lib.flatten (
                    map (key: "${config.device}/${key}") [ "releasekey" "platform" "shared" "media" ]
                    ++ (lib.optional (config.signing.avb.mode == "verity_only") "${config.device}/verity")
                    ++ (lib.optionals (config.androidVersion >= 10) [ "${config.device}/networkstack" ])
                    ++ (lib.optionals (config.androidVersion >= 11) [ "com.android.hotspot2.osulogin" "com.android.wifi.resources" ])
                    ++ (lib.optionals (config.androidVersion >= 12) [ "com.android.connectivity.resources" ])
                    #++ (lib.optionals (config.androidVersion >= 13) [ "com.android.bluetooth" "com.android.adservices.api" "com.android.nearby.halfsheet" "com.android.safetycenter.resources" "com.android.uwb.resources" "com.android.wifi.dialog" ])
                    ++ (lib.optionals (config.androidVersion >= 13) [ "${config.device}/bluetooth" ])
                    ++ (lib.optionals (config.androidVersion >= 13) [ "${config.device}/sdk_sandbox" ])
                    ++ (lib.optional config.signing.apex.enable config.signing.apex.packageNames)
                    ++ (lib.mapAttrsToList
                        (name: prebuilt: prebuilt.certificate)
                        (lib.filterAttrs (name: prebuilt: prebuilt.enable && prebuilt.certificate != "PRESIGNED") config.apps.prebuilt))
                    ));
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

      prebuiltImages = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
        description = ''
          A list of prebuilt images to be added to target-files.
        '';
      };

      avb = {
        enable = mkEnableOption "AVB signing";

        # TODO: Refactor
        mode = mkOption {
          type = types.enum [ "verity_only" "vbmeta_simple" "vbmeta_chained" "vbmeta_chained_v2" ];
          default  = "vbmeta_chained";
          description = "Mode of AVB signing to use.";
        };

        fingerprint = mkOption {
          type = types.strMatching "[0-9A-F]{64}";
          apply = lib.toUpper;
          description = "SHA256 hash of `avb_pkmd.bin`. Should be set automatically based on file under `keyStorePath` if `signing.enable = true`";
        };

        verityCert = mkOption {
          type = types.path;
          description = "Verity certificate for AVB. e.g. in x509 DER format.x509.pem. Only needed if signing.avb.mode = \"verity_only\"";
        };
      };

      apex = {
        enable = mkEnableOption "signing APEX packages";

        packageNames = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "APEX packages which need to be signed";
        };
      };

      keyStorePath = mkOption {
        type = types.either types.str types.path;
        description = ''
          String containing absolute path to generated keys for signing or relative path if your keys are encrypted with sops.
          This must be a _string_ and not a "nix path" to ensure that your plain-text secret keys are not imported into the public `/nix/store`,
          if you do not enable sops encryption. Read the documentation for sopsDecrypt.keyType for more details.

          If this value is an absolute path, make sure to add this path to extra-sandbox-paths in your nix config or pass --extra-sandbox-paths
          to the nix cli so that these keys are available.
        '';
        example = "/var/secrets/android-keys";
      };

      sopsDecrypt = {
        enable = mkEnableOption "decrypt key files using sops";
        keyType = mkOption {
          type = types.enum ["age" "pgp"];
          description = ''
            denotes the kind of key passed to this module:
              * age - the key refers to an age keys.txt file that contains the age key(s), one line per key
              * pgp - the key refers to a pgp public key and the private key will need to be read from config.signing.sopsDecrypt.gpgHome

            make sure to add `--extra-sandbox-paths "$GPG_HOME"` to the nix cli invocation to ensure this path is readable.

            DO NOT CHECK YOUR PRIVATE KEY INTO GIT!!
          '';
        };
        key = mkOption {
          type = types.oneOf [types.str types.path];
          description = "see keyType";
        };
        sopsConfig = mkOption {
          type = types.path;
          description = ''
            config file for sops to use to choose a private key from those provided -- refer to https://github.com/mozilla/sops/ for details on how to provide this file.
          '';
        };
        gpgHome = mkOption {
          type = types.nullOr types.str;
          description = "see keyType";
        };
      };
    };
  };

  config = let
    testKeysStorePath = config.source.dirs."build/make".src + /target/product/security;
  in {
    assertions = [
      {
        assertion = (builtins.length cfg.prebuiltImages) != 0 -> config.androidVersion == 12;
        message = "The --prebuilt-image patch is only applied to Android 12";
      }
    ];

    signing.keyStorePath = mkIf (!config.signing.enable) (mkDefault testKeysStorePath);
    signing.avb.fingerprint = mkIf config.signing.enable (mkOptionDefault
      (pkgs.robotnix.sha256Fingerprint (config.build.signing.withKeys config.signing.keyStorePath) "$KEYSDIR/${config.device}/avb_pkmd.bin"));
    signing.avb.verityCert = mkIf config.signing.enable (mkOptionDefault (putInStore "${config.signing.keyStorePath}/${config.device}/verity.x509.pem"));

    signing.apex.enable = mkIf (config.androidVersion >= 10) (mkDefault true);
    # TODO: Some of these apex packages share the same underlying keys. We should try to match that. See META/apexkeys.txt from  target-files
    signing.apex.packageNames = map (s: "com.android.${s}") (
      lib.optionals (config.androidVersion == 10) [
        "runtime.release"
      ] ++ lib.optionals (config.androidVersion >= 10) [
        "conscrypt" "media" "media.swcodec" "resolv" "tzdata"
      ] ++ lib.optionals (config.androidVersion == 11) [
        "art.release" "vndk.v27"
      ] ++ lib.optionals (config.androidVersion >= 11) [
        "adbd" "cellbroadcast" "extservices" "i18n" "ipsec" "mediaprovider"
        "neuralnetworks" "os.statsd" "permission" "runtime" "sdkext"
        "telephony" "tethering" "wifi" "vndk.current" "vndk.v28" "vndk.v29"
      ] ++ lib.optionals (config.androidVersion >= 12) [
        "appsearch" "art" "art.debug" "art.host" "art.testing" "compos" "geotz"
        "scheduling" "support.apexer" "tethering.inprocess" "virt"
        "vndk.current.on_vendor" "vndk.v30"
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
      ++ lib.optionals ((config.androidVersion >= 10) && (cfg.avb.mode != "verity_only")) [
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
      // lib.optionalAttrs (config.androidVersion >= 10) {
        "build/make/target/product/security/networkstack" = "${config.device}/networkstack";
      }
      // lib.optionalAttrs (config.androidVersion == 11) {
        "frameworks/base/packages/OsuLogin/certs/com.android.hotspot2.osulogin" = "com.android.hotspot2.osulogin";
        "frameworks/opt/net/wifi/service/resources-certs/com.android.wifi.resources" = "com.android.wifi.resources";
      }
      // lib.optionalAttrs (config.androidVersion >= 12) {
        # Paths to OsuLogin and com.android.wifi have changed
        "packages/modules/Wifi/OsuLogin/certs/com.android.hotspot2.osulogin" = "com.android.hotspot2.osulogin";
        "packages/modules/Wifi/service/ServiceWifiResources/resources-certs/com.android.wifi.resources" = "com.android.wifi.resources";
        "packages/modules/Connectivity/service/ServiceConnectivityResources/resources-certs/com.android.connectivity.resources" = "com.android.connectivity.resources";
      }
      // lib.optionalAttrs (config.androidVersion >= 13) {
        "build/make/target/product/security/bluetooth" = "${config.device}/bluetooth";
        "build/make/target/product/security/sdk_sandbox" = "${config.device}/sdk_sandbox";
      }
      # App-specific keys
      // lib.mapAttrs'
        (name: prebuilt: lib.nameValuePair "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}" prebuilt.certificate)
        config.apps.prebuilt;
    in
      lib.mapAttrsToList (from: to: "--key_mapping ${from}=$KEYSDIR/${to}") keyMappings
      ++ lib.optionals cfg.avb.enable avbFlags
      ++ lib.optionals cfg.apex.enable (map (k: "--extra_apks ${k}.apex=$KEYSDIR/${k} --extra_apex_payload_key ${k}.apex=$KEYSDIR/${k}.pem") cfg.apex.packageNames)
      ++ lib.optionals (builtins.length cfg.prebuiltImages != 0) (map (image: "--prebuilt_image ${image}") cfg.prebuiltImages);

    otaArgs =
      if config.signing.enable
      then [ "-k $KEYSDIR/${config.device}/releasekey" ]
      else [ "-k ${config.source.dirs."build/make".src}/target/product/security/testkey" ];

    build.generateKeysScript = let
      # Get a bunch of utilities to generate keys
      keyTools = pkgs.runCommandCC "android-key-tools" { buildInputs = [ (if config.androidVersion >= 12 then pkgs.python3 else pkgs.python2) ]; } ''
        mkdir -p $out/bin

        cp ${config.source.dirs."development".src}/tools/make_key $out/bin/make_key
        substituteInPlace $out/bin/make_key --replace openssl ${lib.getBin pkgs.openssl}/bin/openssl

        cc -o $out/bin/generate_verity_key \
          ${config.source.dirs."system/extras".src}/verity/generate_verity_key.c \
          ${config.source.dirs."system/core".src}/libcrypto_utils/android_pubkey.c${lib.optionalString (config.androidVersion >= 12) "pp"} \
          -I ${config.source.dirs."system/core".src}/libcrypto_utils/include/ \
          -I ${pkgs.boringssl.dev}/include ${pkgs.boringssl}/lib/libssl.a ${pkgs.boringssl}/lib/libcrypto.a -lpthread

        cp ${config.source.dirs."external/avb".src}/avbtool $out/bin/avbtool

        patchShebangs $out/bin
      '';
    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    in pkgs.writeShellScript "generate_keys.sh" ''
      set -euo pipefail

      if [[ "$#" -ne 1 ]]; then
        echo "Usage: $0 <keysdir>"
        echo "$#"
        exit 1
      fi

      mkdir -p "$1"
      cd "$1"

      export PATH=${lib.getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      KEYS=( ${toString keysToGenerate} )
      APEX_KEYS=( ${lib.optionalString config.signing.apex.enable (toString config.signing.apex.packageNames)} )

      mkdir -p "${config.device}"

      for key in "''${KEYS[@]}"; do
        if [[ ! -e "$key".pk8 ]]; then
          echo "Generating $key key"
          # make_key exits with unsuccessful code 1 instead of 0
          make_key "$key" "/CN=Robotnix ''${key/\// }/" && exit 1
        else
          echo "Skipping generating $key key since it is already exists"
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

      ${lib.optionalString (config.signing.avb.mode == "verity_only") ''
      if [[ ! -e "${config.device}/verity_key.pub" ]]; then
          generate_verity_key -convert ${config.device}/verity.x509.pem ${config.device}/verity_key
      fi
      ''}

      ${lib.optionalString (config.signing.avb.mode != "verity_only") ''
      if [[ ! -e "${config.device}/avb.pem" ]]; then
        # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
        echo "Generating Device AVB key"
        openssl genrsa -out ${config.device}/avb.pem 2048
        avbtool extract_public_key --key ${config.device}/avb.pem --output ${config.device}/avb_pkmd.bin
      else
        echo "Skipping generating device AVB key since it is already exists"
      fi
      ''}
    '';

    # Check that all needed keys are available.
    # TODO: Remove code duplicated with generate_keys.sh
    build.verifyKeysScript = pkgs.writeShellScript "verify_keys.sh" ''
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

      ${lib.optionalString (config.signing.avb.mode == "verity_only") ''
      if [[ ! -e "${config.device}/verity_key.pub" ]]; then
        echo "Missing verity_key.pub"
        RETVAL=1
      fi
      ''}

      ${lib.optionalString (config.signing.avb.mode != "verity_only") ''
      if [[ ! -e "${config.device}/avb.pem" ]]; then
        echo "Missing Device AVB key"
        RETVAL=1
      fi
      ''}

      if [[ "$RETVAL" -ne 0 ]]; then
        echo Certain keys were missing from KEYSDIR. Have you run generateKeysScript?
        echo Additionally, some robotnix configuration options require that you re-run
        echo generateKeysScript to create additional new keys.  This should not overwrite
        echo existing keys.
      fi
      exit $RETVAL
    '';

    build.signing.withKeys = keysDir: script: ''
      export KEYSDIR=${keysDir}
      if [[ "$KEYSDIR" ]]; then
        if [[ ! -d "$KEYSDIR" ]]; then
          echo 'Missing KEYSDIR directory, did you use "--option extra-sandbox-paths /keys=..." ?'
          exit 1
        fi
        ${lib.optionalString config.signing.enable "${config.build.verifyKeysScript} \"$KEYSDIR\" || exit 1"}
        NEW_KEYSDIR=$(mktemp -d /dev/shm/robotnix_keys.XXXXXXXXXX)
        trap "rm -rf \"$NEW_KEYSDIR\"" EXIT

        # copy the keys over
        export SOPS_AGE_KEY_FILE=${lib.optionalString (config.signing.sopsDecrypt.enable && config.signing.sopsDecrypt.keyType == "age") config.signing.sopsDecrypt.key};
        export SOPS_PGP_FP=${lib.optionalString (config.signing.sopsDecrypt.enable && config.signing.sopsDecrypt.keyType == "pgp") config.signing.sopsDecrypt.key};
        export GNUPGHOME=${lib.optionalString (config.signing.sopsDecrypt.enable && config.signing.sopsDecrypt.keyType == "pgp" && builtins.hasAttr "gpgHome" config.signing.sopsDecrypt) (builtins.getAttr "gpgHome" config.signing.sopsDecrypt)};
        if [ -n $GNUPGHOME ]; then export HOME=$(dirname $GNUPGHOME); fi

        (cd $KEYSDIR
        for f in `find . -type f`; do
          mkdir -p $(dirname $NEW_KEYSDIR/''${f#./})
          ${if config.signing.sopsDecrypt.enable then "sops --config ${config.signing.sopsDecrypt.sopsConfig} -d $f >" else "cp $f"} $NEW_KEYSDIR/''${f#./}
        done)

        # now set the new KEYSDIR and run the script
        KEYSDIR=$NEW_KEYSDIR
        chmod u+w -R "$NEW_KEYSDIR"
        ${script}
      fi
    '';
  };

  imports = [
    (mkRenamedOptionModule [ "keyStorePath" ] [ "signing" "keyStorePath" ])
  ];
}
