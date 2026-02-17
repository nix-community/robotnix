# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkEnableOption
    mkDefault
    mkOptionDefault
    mkRenamedOptionModule
    types
    ;

  cfg = config.signing;

  # TODO: Find a better way to do this?
  putInStore = path: if (lib.hasPrefix builtins.storeDir path) then path else (/. + path);

  algorithm = "SHA256_RSA${builtins.toString cfg.avb.size}";
  keysToGenerate = lib.unique (
    (builtins.attrValues cfg.keyMappings) ++ (builtins.attrValues cfg.extraApks)
  );
in
{
  options = {
    signing = {
      avbFlags = mkOption {
        default = [ ];
        type = types.listOf types.str;
        internal = true;
        description = ''
          The AVB-related flags to pass to sign_target_files_apks.
        '';
      };

      keyMappings = mkOption {
        default = { };
        type = types.attrsOf types.str;
        internal = true;
        description = ''
          The --key_mapping options to pass to sign_target_files_apks.
        '';
      };

      extraApks = mkOption {
        default = { };
        type = types.attrsOf types.str;
        internal = true;
        description = ''
          The --extra_apks options to pass to sign_target_files_apks.
        '';
      };

      extraApexPayloadKeys = mkOption {
        default = { };
        type = types.attrsOf types.str;
        internal = true;
        description = ''
          The --extra_apex_payload_key options to pass to sign_target_files_apks.
        '';
      };

      apkFlags = mkOption {
        default = [ ];
        type = types.listOf types.str;
        internal = true;
        description = ''
          The APK-related flags to pass to sign_target_files_apks.
        '';
      };

      apexFlags = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          The APEX-related flags to pass to sign_target_files_apks.
        '';
      };

      extraFlags = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          Additional non-APK-nor-APEX-related flags to pass to sign_target_files_apks.
        '';
      };

      signTargetFilesArgs = mkOption {
        default = [ ];
        type = types.listOf types.str;
        internal = true;
        description = ''
          The arguments to pass to sign_target_files_apks.
        '';
      };

      prebuiltImages = mkOption {
        default = [ ];
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
          type = types.enum [
            "vbmeta_simple"
            "vbmeta_chained"
            "vbmeta_chained_v2"
          ];
          default = "vbmeta_simple";
          description = "Mode of AVB signing to use.";
        };

        size = mkOption {
          type = types.number;
          default = 4096;
          description = "Size of the SHA256 RSA keys";
        };
      };

      apex = {
        enable = mkEnableOption "signing APEX packages";

        packageNames = mkOption {
          default = [ ];
          type = types.listOf types.str;
          description = "APEX packages which need to be signed";
        };
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = (builtins.length cfg.prebuiltImages) != 0 -> config.androidVersion == 12;
        message = "The --prebuilt-image patch is only applied to Android 12";
      }
    ];

    signing.apex.enable = mkIf (config.androidVersion >= 10) (mkDefault true);
    # TODO: Some of these apex packages share the same underlying keys. We should try to match that. See META/apexkeys.txt from  target-files
    signing.apex.packageNames = map (s: "com.android.${s}") (
      lib.optionals (config.androidVersion == 10) [
        "runtime.release"
      ]
      ++ lib.optionals (config.androidVersion >= 10) [
        "conscrypt"
        "media"
        "media.swcodec"
        "resolv"
        "tzdata"
      ]
      ++ lib.optionals (config.androidVersion == 11) [
        "art.release"
        "vndk.v27"
      ]
      ++ lib.optionals (config.androidVersion >= 11) [
        "adbd"
        "cellbroadcast"
        "extservices"
        "i18n"
        "ipsec"
        "mediaprovider"
        "neuralnetworks"
        "os.statsd"
        "permission"
        "runtime"
        "sdkext"
        "telephony"
        "tethering"
        "wifi"
        "vndk.current"
        "vndk.v28"
        "vndk.v29"
      ]
      ++ lib.optionals (config.androidVersion >= 12) [
        "appsearch"
        "art"
        "art.debug"
        "art.host"
        "art.testing"
        "compos"
        "geotz"
        "scheduling"
        "support.apexer"
        "tethering.inprocess"
        "virt"
        "vndk.current.on_vendor"
        "vndk.v30"
      ]
      ++ lib.optionals (config.androidVersion >= 13) [
        "adservices"
        "btservices"
        "ondevicepersonalization"
        "uwb"
      ]
      ++ lib.optionals (config.androidVersion >= 14) [
        "configinfrastructure"
        "devicelock"
        "healthfitness"
        "rkpd"
        "hardware.cas"
      ]
      ++ lib.optionals (config.androidVersion >= 15) [
        "nfcservices"
        "profiling"
      ]
      ++ lib.optionals (config.androidVersion >= 16) [
        "bt"
        "crashrecovery"
        "uprobestats"
        "hardware.biometrics.face.virtual"
        "hardware.biometrics.fingerprint.virtual"
        "telephonycore"
      ]
    );

    signing = {
      avbFlags =
        {
          vbmeta_simple = [
            "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem"
            "--avb_vbmeta_algorithm ${algorithm}"
          ];
          vbmeta_chained = [
            "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem"
            "--avb_vbmeta_algorithm ${algorithm}"
            "--avb_system_key $KEYSDIR/${config.device}/avb.pem"
            "--avb_system_algorithm ${algorithm}"
          ];
          vbmeta_chained_v2 = [
            "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem"
            "--avb_vbmeta_algorithm ${algorithm}"
            "--avb_system_key $KEYSDIR/${config.device}/avb.pem"
            "--avb_system_algorithm ${algorithm}"
            "--avb_vbmeta_system_key $KEYSDIR/${config.device}/avb.pem"
            "--avb_vbmeta_system_algorithm ${algorithm}"
          ];
        }
        .${cfg.avb.mode};

      keyMappings =
        {
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
          "frameworks/base/packages/OsuLogin/certs/com.android.hotspot2.osulogin" =
            "com.android.hotspot2.osulogin";
          "frameworks/opt/net/wifi/service/resources-certs/com.android.wifi.resources" =
            "com.android.wifi.resources";
        }
        // lib.optionalAttrs (config.androidVersion >= 12) {
          # Paths to OsuLogin and com.android.wifi have changed
          "packages/modules/Wifi/OsuLogin/certs/com.android.hotspot2.osulogin" =
            "com.android.hotspot2.osulogin";
          "packages/modules/Wifi/service/ServiceWifiResources/resources-certs/com.android.wifi.resources" =
            "com.android.wifi.resources";
          "packages/modules/Connectivity/service/ServiceConnectivityResources/resources-certs/com.android.connectivity.resources" =
            "com.android.connectivity.resources";
        }
        // lib.optionalAttrs (config.androidVersion >= 13) {
          "packages/modules/AdServices/adservices/apk/com.android.adservices.api" =
            "com.android.adservices.api";
          "packages/modules/Permission/SafetyCenter/Resources/com.android.safetycenter.resources" =
            "com.android.safetycenter.resources";
          "packages/modules/Connectivity/nearby/halfsheet/apk-certs/com.android.nearby.halfsheet" =
            "com.android.nearby.halfsheet";
          "packages/modules/Uwb/service/ServiceUwbResources/resources-certs/com.android.uwb.resources" =
            "com.android.uwb.resources";
          "packages/modules/Wifi/WifiDialog/certs/com.android.wifi.dialog" = "com.android.wifi.dialog";
        }
        # App-specific keys
        // lib.mapAttrs' (
          name: prebuilt:
          lib.nameValuePair "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}" prebuilt.certificate
        ) (lib.filterAttrs (_: acfg: acfg.enable && acfg.certificate != "PRESIGNED") config.apps.prebuilt);

      extraApks = builtins.listToAttrs (
        map (name: {
          name = "${name}.apex";
          value = name;
        }) cfg.apex.packageNames
      );
      extraApexPayloadKeys = builtins.listToAttrs (
        map (name: {
          name = "${name}.apex";
          value = "${name}.pem";
        }) cfg.apex.packageNames
      );

      apkFlags =
        (lib.mapAttrsToList (from: to: "--key_mapping ${from}=$KEYSDIR/${to}") cfg.keyMappings)
        ++ (lib.mapAttrsToList (apk: key: "--extra_apks ${apk}=$KEYSDIR/${key}") cfg.extraApks);
      apexFlags = lib.mapAttrsToList (
        apex: key: "--extra_apex_payload_key ${apex}=$KEYSDIR/${key}"
      ) cfg.extraApexPayloadKeys;

      extraFlags = map (image: "--prebuilt_image ${image}") cfg.prebuiltImages;

      signTargetFilesArgs = cfg.avbFlags ++ cfg.apkFlags ++ cfg.apexFlags ++ cfg.extraFlags;
    };

    otaArgs = [ "-k ${config.source.dirs."build/make".src}/target/product/security/testkey" ];

    build.generateKeysScript =
      let
        # Get a bunch of utilities to generate keys

        # avbtool has been renamed to avbtool.py
        # History about the change:
        # * Android 10: There's only avbtool
        # * Android 11: Adds a symlink avbtool.py, which points to avbtool
        # * Android 12: Swaps the two above, now there's a symlink called avbtool
        #               which points to avbtool.py
        # * Android 14: Now there's only avbtool.py, the avbtool symlink has been
        #               removed
        avbtoolFilename = if config.androidVersion <= 10 then "avbtool" else "avbtool.py";
        keyTools =
          pkgs.runCommandCC "android-key-tools"
            { buildInputs = [ (if config.androidVersion >= 12 then pkgs.python3 else pkgs.python2) ]; }
            ''
              mkdir -p $out/bin

              cp --no-preserve=mode ${config.source.dirs."development".src}/tools/make_key $out/bin/make_key
              chmod +x $out/bin/make_key
              patch $out/bin/make_key ${./make_key_fix_return_code.patch}

              substituteInPlace $out/bin/make_key --replace openssl ${lib.getBin pkgs.openssl}/bin/openssl

              cp ${config.source.dirs."external/avb".src}/${avbtoolFilename} $out/bin/avbtool

              patchShebangs $out/bin
            '';
        # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
        # Generate avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
      in
      pkgs.writeShellScript "generate_keys.sh" ''
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
            # echo a newline into make_key to disable key encryption, see
            # https://github.com/nix-community/robotnix/pull/355#issuecomment-3867184497
            echo | make_key "$key" "/CN=Robotnix ''${key/\// }/"
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

        if [[ ! -e "${config.device}/avb.pem" ]]; then
          echo "Generating Device AVB key"
          openssl genrsa -out ${config.device}/avb.pem ${builtins.toString cfg.avb.size}
          avbtool extract_public_key --key ${config.device}/avb.pem --output ${config.device}/avb_pkmd.bin
        else
          echo "Skipping generating device AVB key since it is already exists"
        fi
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
      MISSING_KEYS=0

      for key in "''${KEYS[@]}"; do
        if [[ ! -e "$key".pk8 ]]; then
          echo "Missing $key key"
          MISSING_KEYS=1
        fi
      done

      for key in "''${APEX_KEYS[@]}"; do
        if [[ ! -e "$key".pem ]]; then
          echo "Missing $key APEX AVB key"
          MISSING_KEYS=1
        fi
      done

      if [[ ! -e "${config.device}/avb.pem" ]]; then
        echo "Missing Device AVB key"
        MISSING_KEYS=1
      else
        KEYSIZE=$(${lib.getExe pkgs.openssl} rsa -in "${config.device}/avb.pem" -text 2>/dev/null | grep -E "Private-Key: \(([0-9]+) bit, 2 primes\)" | tr -d "(" | awk '{ print $2 }')
        if [[ "$KEYSIZE" -ne ${toString config.signing.avb.size} ]]; then
          echo "Device AVB key in $1 has wrong size ($KEYSIZE bits), but ${toString config.signing.avb.size} bits were expected."
          echo "Either rotate your AVB signing key, or set \`signing.avb.size = $KEYSIZE;\`."
          RETVAL=1
        fi
      fi

      if [[ "$MISSING_KEYS" -ne 0 ]]; then
        echo Certain keys were missing from KEYSDIR. Have you run generateKeysScript?
        echo Additionally, some robotnix configuration options require that you re-run
        echo generateKeysScript to create additional new keys.  This should not overwrite
        echo existing keys.
        exit 1
      fi
      exit $RETVAL
    '';
  };
}
