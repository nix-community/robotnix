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

  avbAlgorithm = "SHA256_RSA${builtins.toString cfg.avb.size}";
  keysToGenerate = lib.unique (
    (builtins.attrValues cfg.keyMappings) ++ (builtins.attrValues cfg.extraApks)
  );

  signapkKeyNameMap =
    if config.signing.pkcs11.enable then
      (x: config.signing.pkcs11.certificateLabels.${x})
    else
      (x: "$KEYSDIR/${x}");

  avbtoolKeyMap =
    if config.signing.pkcs11.enable then
      (x: config.signing.pkcs11.privateKeyLabels.${x})
    else
      (x: "$KEYSDIR/${x}.pem");
in
{
  options = {
    signing = {
      # Currently, make_key hardcodes a key size of 4096 bits.
      # This might change in the future and wreak havoc to our PKCS#11 signing,
      # so we future-proof it by checking in verifyKeysScript that the key size
      # is, indeed, still 4096 bit.
      apkKeySize = mkOption {
        default = 4096;
        type = types.enum [ 4096 ];
        internal = true;
        description = '''';
      };

      avbFlags = mkOption {
        default = [ ];
        type = types.listOf types.str;
        internal = true;
        description = ''
          The AVB-related flags to pass to sign_target_files_apks.
        '';
      };

      keyCN = mkOption {
        default = "Robotnix";
        type = types.str;
        internal = true;
        description = ''
          The CN to generate keys for
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
          default = if lib.versionAtLeast config.stateVersion "2" then "vbmeta_simple" else "vbmeta_chained";
          description = "Mode of AVB signing to use.";
        };

        # TODO this is still hardcoded in a number of places.
        key = mkOption {
          type = types.str;
          default = "${config.device}/avb";
          defaultText = "\${config.device}/avb";
          description = "The identifier of the AVB key to use.";
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

      otaFlags = mkOption {
        default = [ ];
        type = types.listOf types.str;
        internal = true;
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = (builtins.length cfg.prebuiltImages) != 0 -> config.androidVersion == 12;
        message = "The --prebuilt-image patch is only applied to Android 12";
      }
      {
        assertion = (lib.versionAtLeast config.stateVersion "3") -> config.signing.avb.size == 4096;
        message = ''
          Starting with stateVersion = "3", signing.avb.size must be set to 4096.
        '';
      }
    ];

    source.dirs."build/make".patches = [
      ./0001-sign_target_files_apks-Add-pkmd-CLI-args.patch
      ./0002-signapk-add-keyStorePinFile-option.patch
      ./0003-add-public_key_map-option.patch
      ./0004-add-dedicated-private-key-suffix-option-for-SignFile.patch
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
            ''--avb_vbmeta_key "${avbtoolKeyMap cfg.avb.key}"''
            "--avb_vbmeta_algorithm ${avbAlgorithm}"
          ];
          vbmeta_chained = [
            ''--avb_vbmeta_key "${avbtoolKeyMap cfg.avb.key}"''
            ''--avb_vbmeta_algorithm ${avbAlgorithm}''
            ''--avb_system_key "${avbtoolKeyMap cfg.avb.key}"''
            ''--avb_system_algorithm ${avbAlgorithm}''
          ];
          vbmeta_chained_v2 = [
            ''--avb_vbmeta_key "${avbtoolKeyMap cfg.avb.key}"''
            ''--avb_vbmeta_algorithm ${avbAlgorithm}''
            ''--avb_system_key "${avbtoolKeyMap cfg.avb.key}"''
            ''--avb_system_algorithm ${avbAlgorithm}''
            ''--avb_vbmeta_system_key "${avbtoolKeyMap cfg.avb.key}"''
            ''--avb_vbmeta_system_algorithm ${avbAlgorithm}''
          ];
        }
        .${cfg.avb.mode}
        ++ lib.optionals
          ((config.androidVersion >= 10) && (cfg.avb.mode != "verity_only") && config.stateVersion == "1")
          [
            ''--avb_system_other_key "${avbtoolKeyMap cfg.avb.key}"''
            ''--avb_system_other_algorithm ${avbAlgorithm}''
          ];

      keyMappings =
        {
          # Default key mappings from sign_target_files_apks.py
          "build/make/target/product/security/devkey" = "${config.device}/releasekey";
          "build/make/target/product/security/testkey" = "${config.device}/releasekey";
          "build/make/target/product/security/media" = "${config.device}/media";
          "build/make/target/product/security/shared" = "${config.device}/shared";
          "build/make/target/product/security/platform" = "${config.device}/platform";
          "build/make/target/product/security/sdk_sandbox" = "${config.device}/sdk_sandbox";
          "build/make/target/product/security/nfc" = "${config.device}/nfc";
          "build/make/target/product/security/networkstack" = "${config.device}/networkstack";
        }
        # App-specific keys
        // lib.mapAttrs' (
          name: prebuilt:
          lib.nameValuePair "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}" prebuilt.certificate
        ) (lib.filterAttrs (_: acfg: acfg.enable && acfg.certificate != "PRESIGNED") config.apps.prebuilt);

      extraApks =
        (builtins.listToAttrs (
          map (name: {
            name = "${name}.apex";
            value = if lib.versionAtLeast config.stateVersion "3" then "${config.device}/releasekey" else name;
          }) cfg.apex.packageNames
        ))
        // (lib.optionalAttrs (lib.versionAtLeast config.stateVersion "3") {
          "AdServicesApk.apk" = "${config.device}/releasekey";
          "com.android.appsearch.apk.apk" = "${config.device}/releasekey";
          "HalfSheetUX.apk" = "${config.device}/releasekey";
          "HealthConnectBackupRestore.apk" = "${config.device}/releasekey";
          "HealthConnectController.apk" = "${config.device}/releasekey";
          "FederatedCompute.apk" = "${config.device}/releasekey";
          "SafetyCenterResources.apk" = "${config.device}/releasekey";
          "ServiceConnectivityResources.apk" = "${config.device}/releasekey";
          "ServiceUwbResources.apk" = "${config.device}/releasekey";
          "OsuLogin.apk" = "${config.device}/releasekey";
          "ServiceWifiResources.apk" = "${config.device}/releasekey";
          "WifiDialog.apk" = "${config.device}/releasekey";
        });
      extraApexPayloadKeys = builtins.listToAttrs (
        map (name: {
          name = "${name}.apex";
          value = if lib.versionAtLeast config.stateVersion "3" then "${config.device}/avb" else "${name}";
        }) cfg.apex.packageNames
      );

      apkFlags =
        (lib.mapAttrsToList (from: to: "--key_mapping ${from}=\"${signapkKeyNameMap to}\"") cfg.keyMappings)
        ++ (lib.mapAttrsToList (
          apk: key: "--extra_apks ${apk}=\"${signapkKeyNameMap key}\""
        ) cfg.extraApks);
      apexFlags = lib.mapAttrsToList (
        apex: key: "--extra_apex_payload_key ${apex}=\"${avbtoolKeyMap key}\""
      ) cfg.extraApexPayloadKeys;

      extraFlags = map (image: "--prebuilt_image ${image}") cfg.prebuiltImages;

      signTargetFilesArgs = cfg.avbFlags ++ cfg.apkFlags ++ cfg.apexFlags ++ cfg.extraFlags;

      otaFlags = lib.mkIf (!cfg.pkcs11.enable) [
        "-k \"$KEYSDIR/keys/releasekey\""
      ];
    };

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
        ${lib.optionalString (!lib.versionAtLeast config.stateVersion "3") ''
          APEX_KEYS=( ${lib.optionalString config.signing.apex.enable (toString config.signing.apex.packageNames)} )
        ''}

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

        ${lib.optionalString (!lib.versionAtLeast config.stateVersion "3") ''
          for key in "''${APEX_KEYS[@]}"; do
            if [[ ! -e "$key".pem ]]; then
              echo "Generating $key APEX AVB key"
              openssl genrsa -out "$key".pem 4096
              avbtool extract_public_key --key "$key".pem --output "$key".avbpubkey
            else
              echo "Skipping generating $key APEX key since it is already exists"
            fi
          done
        ''}

        if [[ ! -e "${cfg.avb.key}.pem" ]]; then
          echo "Generating Device AVB key"
          openssl genrsa -out ${cfg.avb.key}.pem ${builtins.toString cfg.avb.size}
          avbtool extract_public_key --key ${cfg.avb.key}.pem --output ${cfg.avb.key}_pkmd.bin
        else
          echo "Skipping generating device AVB key since it is already exists"
        fi

        if [[ ! -e "${cfg.avb.key}.x509.pem" ]]; then
          echo "Generating Device AVB certificate"
          openssl req -key ${cfg.avb.key}.pem -x509 -days 3650 -subj "/CN=Robotnix avb/" -out ${cfg.avb.key}.x509.pem
        else
          echo "Skipping generating device AVB certificate since it is already exists"
        fi
      '';

    # Check that all needed keys are available.
    # TODO: Remove code duplicated with generate_keys.sh
    build.verifyKeysScript = pkgs.writeShellScript "verify_keys.sh" ''
      set -euo pipefail
      PATH=${
        lib.makeBinPath (
          with pkgs;
          [
            coreutils
            openssl
            gnugrep
            gawk
          ]
        )
      }

      if [[ "$#" -ne 1 ]]; then
        echo "Usage: $0 <keysdir>"
        exit 1
      fi

      cd "$1"

      KEYS=( ${toString keysToGenerate} )
      ${lib.optionalString (!lib.versionAtLeast config.stateVersion "3") ''
        APEX_KEYS=( ${lib.optionalString config.signing.apex.enable (toString config.signing.apex.packageNames)} )
      ''}

      RETVAL=0
      MISSING_KEYS=0

      for key in "''${KEYS[@]}"; do
        if [[ ! -e "$key".x509.pem ]]; then
          echo "Missing $key certificate"
          MISSING_KEYS=1
        fi
        KEYSIZE=$(openssl x509 -in "$key.x509.pem" -text -noout | grep "Public-Key" | tr -d '(' | awk '{ print $2 }')
        if [ "$KEYSIZE" != ${toString config.signing.apkKeySize} ]; then
          echo "APK certificate $key has wrong size ($KEYSIZE bits), but ${toString config.signing.avb.size} were expected."
          RETVAL=1
        fi
      done

      ${lib.optionalString (!lib.versionAtLeast config.stateVersion "3") ''
        for key in "''${APEX_KEYS[@]}"; do
          if [[ ! -e "$key".pem ]]; then
            echo "Missing $key APEX AVB key"
            MISSING_KEYS=1
          fi
        done
      ''}

      if [[ ! -e "${config.device}/avb.x509.pem" ]]; then
        echo "Missing device AVB certificate"
        MISSING_KEYS=1
      else
        KEYSIZE=$(openssl x509 -in "${config.device}/avb.x509.pem" -noout -text | grep "Public-Key" | tr -d "(" | awk '{ print $2 }')
        if [[ "$KEYSIZE" -ne ${toString config.signing.avb.size} ]]; then
          echo "Device AVB certificate in $1 has wrong size ($KEYSIZE bits), but ${toString config.signing.avb.size} bits were expected."
          echo "Either rotate your AVB certificate, or set \`signing.avb.size = $KEYSIZE;\`."
          RETVAL=1
        fi
      fi

      if [[ "$MISSING_KEYS" -ne 0 ]]; then
        echo Certain keys were missing from KEYSDIR. Have you run generateKeysScript?
        echo Additionally, some robotnix configuration options require that you re-run
        echo generateKeysScript to create additional new keys.  This should not overwrite
        echo any existing keys.
        exit 1
      fi
      exit $RETVAL
    '';
  };
}
