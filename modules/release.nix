{ config, pkgs, lib, ... }:

with lib;
let
  nixdroid-env = pkgs.callPackage ../buildenv.nix {};

  avbFlags = {
    verity_only = [
      "--replace_verity_public_key $KEYSDIR/verity_key.pub"
      "--replace_verity_private_key $KEYSDIR/verity"
      "--replace_verity_keyid $KEYSDIR/verity.x509.pem"
    ];
    vbmeta_simple = [ "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048" ];
    vbmeta_chained = [
      "--avb_vbmeta_key $KEYSDIR/avb.pem"
      "--avb_vbmeta_algorithm SHA256_RSA2048"
      "--avb_system_key $KEYSDIR/avb.pem"
      "--avb_system_algorithm SHA256_RSA2048"
    ] ++ optionals (config.androidVersion == "10") [
      "--avb_system_other_key $KEYSDIR/avb.pem"
      "--avb_system_other_algorithm SHA256_RSA2048"
    ];
  }.${config.avbMode};

  # Signing target files fails in signapk.jar with error -6 unless using this jdk
  jdk = pkgs.callPackage (pkgs.path + /pkgs/development/compilers/openjdk/8.nix) {
    bootjdk = pkgs.callPackage (pkgs.path + /pkgs/development/compilers/openjdk/bootstrap.nix) { version = "8"; };
    inherit (pkgs.gnome2) GConf gnome_vfs;
    minimal = true;
  };

  # TODO: build tools is an overloaded name. See prebuilts/build-tools
  buildTools = pkgs.stdenv.mkDerivation {
    name = "android-build-tools";
    src = config.source.dirs."build/make".contents;
    patches = config.source.dirs."build/make".patches ++ [
      (pkgs.substituteAll {
        src = (../patches + "/${config.androidVersion}" + /buildtools.patch);
        java = "${jdk}/bin/java";
        search_path = config.build.hostTools;
      })
    ];
    buildInputs = with pkgs; [ python ];
    installPhase = ''
      mkdir -p $out
      cp --reflink=auto -r ./tools/* $out
      cp --reflink=auto ${config.source.dirs."system/extras".contents}/verity/{build_verity_metadata.py,boot_signer,verity_signer} $out # Some extra random utilities from elsewhere
    '';
  };

  # Get a bunch of utilities to generate keys
  keyTools = pkgs.runCommandCC "android-key-tools" { buildInputs = with pkgs; [ python pkgconfig boringssl ]; } ''
    mkdir -p $out/bin

    cp ${config.source.dirs."development".contents}/tools/make_key $out/bin/make_key
    substituteInPlace $out/bin/make_key --replace openssl ${getBin pkgs.openssl}/bin/openssl

    cc -o $out/bin/generate_verity_key \
      ${config.source.dirs."system/extras".contents}/verity/generate_verity_key.c \
      ${config.source.dirs."system/core".contents}/libcrypto_utils/android_pubkey.c \
      -I ${config.source.dirs."system/core".contents}/libcrypto_utils/include/ \
      -I ${pkgs.boringssl}/include ${pkgs.boringssl}/lib/libssl.a ${pkgs.boringssl}/lib/libcrypto.a -lpthread

    cp ${config.source.dirs."external/avb".contents}/avbtool $out/bin/avbtool
    patchShebangs $out/bin
  '';

  wrapScript = { commands, keysDir ? "" }: ''
    export PATH=${lib.makeBinPath (with pkgs; [
      config.build.hostTools openssl zip unzip jdk pkgs.getopt hexdump perl toybox
    ])}:${buildTools}:$PATH

    # sign_target_files_apks.py and others require this directory to be here so it has the data to even recognize test-keys
    mkdir -p build/target/product/
    ln -sf ${config.source.dirs."build/make".contents}/target/product/security build/target/product/security

    # build-tools releasetools/common.py hilariously tries to modify the
    # permissions of the source file in ZipWrite. Since signing uses this
    # function with a key, we need to make a temporary copy of our keys so the
    # sandbox doesn't complain if it doesn't have permissions to do so.
    export KEYSDIR=${keysDir}
    if [[ "$KEYSDIR" ]]; then
      if [[ ! -d "$KEYSDIR" ]]; then
        echo 'Missing KEYSDIR directory, did you use "--option extra-sandbox-paths /keys=..." ?'
        exit 1
      fi
      mkdir -p keys_copy
      cp -r $KEYSDIR/* keys_copy/
      KEYSDIR=keys_copy
    fi

    # TODO: Try to get rid of this nixdroid-env wrapper.
    cat << 'EOF' | ${nixdroid-env}/bin/nixdroid-build
    ${commands}
    EOF

    rm -r build  # Unsafe
    if [[ "$KEYSDIR" ]]; then rm -rf keys_copy; fi
  '';

  runWrappedCommand = name: script: args: pkgs.runCommand "${config.device}-${name}-${config.buildNumber}.zip" {} (wrapScript {
    commands = script (args // {out="$out";});
    keysDir = optionalString config.signBuild "/keys/${config.device}";
  });

  signedTargetFilesScript = { targetFiles, out }: ''
    ${buildTools}/releasetools/sign_target_files_apks.py \
      --verbose \
      -o -d $KEYSDIR ${toString avbFlags} \
      ${optionalString (config.androidVersion == "10") "--key_mapping build/target/product/security/networkstack=$KEYSDIR/networkstack"} \
      ${concatMapStringsSep " " (k: "--extra_apks ${k}.apex=$KEYSDIR/${k} --extra_apex_payload_key ${k}.apex=$KEYSDIR/${k}.pem") config.apex.packageNames} \
      ${targetFiles} ${out}
  '';
  otaScript = { targetFiles, prevTargetFiles ? null, out }: ''
    ${buildTools}/releasetools/ota_from_target_files.py  \
      --block ''${KEYSDIR:+-k $KEYSDIR/releasekey} \
      ${optionalString (prevTargetFiles != null) "-i ${prevTargetFiles}"} \
      ${optionalString config.retrofit "--retrofit_dynamic_partitions"} \
      ${targetFiles} ${out}
  '';
  imgScript = { targetFiles, out }: ''${buildTools}/releasetools/img_from_target_files.py ${targetFiles} ${out}'';
  factoryImgScript = { targetFiles, img, out }: ''
      ln -s ${targetFiles} ${config.device}-target_files-${config.buildNumber}.zip || true
      ln -s ${img} ${config.device}-img-${config.buildNumber}.zip || true

      export DEVICE=${config.device};
      export PRODUCT=${config.device};
      export BUILD=${config.buildNumber};
      export VERSION=${toLower config.buildNumber};

      # TODO: What if we don't have vendor.files? Maybe extract and use IFD?
      get_radio_image() {
        grep -Po "require version-$1=\K.+" ${config.build.vendor.files}/vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
      }
      export BOOTLOADER=$(get_radio_image bootloader google_devices/$DEVICE)
      export RADIO=$(get_radio_image baseband google_devices/$DEVICE)

      ${pkgs.runtimeShell} ${config.source.dirs."device/common".contents}/generate-factory-images-common.sh
      mv $PRODUCT-$VERSION-factory-*.zip $out
  '';

  otaMetadata = pkgs.runCommand "${config.device}-${config.channel}" {} ''
    ${pkgs.python3}/bin/python ${./generate_metadata.py} ${config.ota} > $out
  '';
in
{
  options = {
    channel = mkOption {
      default = "stable";
      type = types.strMatching "(stable|beta)";
      description = "Default channel to use for updates (can be modified in app)";
    };

    incremental = mkOption {
      default = false;
      type = types.bool;
      description = "Whether to include an incremental build in otaDir";
    };

    retrofit = mkOption {
      default = false;
      type = types.bool;
      description = "Generate a retrofit OTA for upgrading a device without dynamic partitions";
      # https://source.android.com/devices/tech/ota/dynamic_partitions/ab_legacy#generating-update-packages
    };

    # Build products. Put here for convenience--but it's not a great interface
    unsignedTargetFiles = mkOption { type = types.path; internal = true; };
    signedTargetFiles = mkOption { type = types.path; internal = true; };
    ota = mkOption { type = types.path; internal = true; };
    incrementalOta = mkOption { type = types.path; internal = true; };
    otaDir = mkOption { type = types.path; internal = true; };
    img = mkOption { type = types.path; internal = true; };
    factoryImg = mkOption { type = types.path; internal = true; };
    generateKeysScript = mkOption { type = types.path; internal = true; };
    releaseScript = mkOption { type = types.path; internal = true;};

    prevBuildDir = mkOption { type = types.str; internal = true; };
    prevBuildNumber = mkOption { type = types.str; internal = true; };
    prevTargetFiles = mkOption { type = types.path; internal = true; };

    # Android 10 feature. This just disables the key generation/signing. TODO: Make it change the device configuration as well
    apex.enable = mkEnableOption "apex";

    apex.packageNames = mkOption {
      default = [];
      type = types.listOf types.str;
    };
  };

  config = with config; let # "with config" is ugly--but the scripts below get too verbose otherwise
    targetFiles = if signBuild then signedTargetFiles else unsignedTargetFiles;
  in {
    # These can be used to build these products inside nix. Requires putting the secret keys under /keys in the sandbox
    unsignedTargetFiles = mkDefault (build.android + "/aosp_${device}-target_files-${buildNumber}.zip");
    signedTargetFiles = mkDefault (assert signBuild; runWrappedCommand "signed_target_files" signedTargetFilesScript { targetFiles=unsignedTargetFiles;});
    ota = mkDefault (runWrappedCommand "ota_update" otaScript { inherit targetFiles; });
    incrementalOta = mkDefault (runWrappedCommand "incremental-${prevBuildNumber}" otaScript { inherit targetFiles prevTargetFiles; });
    img = mkDefault (runWrappedCommand "img" imgScript { inherit targetFiles; });
    factoryImg = mkDefault (runWrappedCommand "factory" factoryImgScript { inherit targetFiles img; });

    apex.packageNames = mkIf (apex.enable && (androidVersion == "10"))
      [ "com.android.conscrypt" "com.android.media"
        "com.android.media.swcodec" "com.android.resolv"
        "com.android.runtime.release" "com.android.tzdata"
      ];

    prevBuildNumber = let
        metadata = builtins.readFile (prevBuildDir + "/${device}-${channel}");
      in mkDefault (head (splitString " " metadata));
    prevTargetFiles = mkDefault (prevBuildDir + "/${device}-target_files-${prevBuildNumber}.zip");

    # TODO: target-files aren't necessary to publish--but are useful to include if prevBuildDir is set to otaDir output
    otaDir = pkgs.linkFarm "${device}-otaDir" (
      (map (p: {name=p.name; path=p;}) ([ ota otaMetadata ] ++ (optional incremental incrementalOta)))
      ++ [{ name="${device}-target_files-${buildNumber}.zip"; path=targetFiles; }]
    );

    # TODO: Do this in a temporary directory. It's ugly to make build dir and ./tmp/* dir gets cleared in these scripts too.
    # Maybe just remove this script? It's definitely complicated--and often untested
    releaseScript = mkDefault (pkgs.writeScript "release.sh" (''
      #!${pkgs.runtimeShell}
      export PREV_BUILDNUMBER=$2
      '' + (wrapScript { keysDir="$1"; commands=''
      if [[ "$KEYSDIR" ]]; then
        echo Signing target files
        ${signedTargetFilesScript { targetFiles=unsignedTargetFiles; out=signedTargetFiles.name; }} || exit 1
      fi
      echo Building OTA zip
      ${otaScript { targetFiles=signedTargetFiles.name; out=ota.name; }} || exit 1
      echo Building incremental OTA zip
      if [[ ! -z "$PREV_BUILDNUMBER" ]]; then
        ${otaScript {
          targetFiles=signedTargetFiles.name;
          prevTargetFiles="${device}-target_files-$PREV_BUILDNUMBER.zip";
          out="${device}-incremental-$PREV_BUILDNUMBER-${buildNumber}.zip";
        }} || exit 1
      fi
      echo Building .img file
      ${imgScript { targetFiles=signedTargetFiles.name; out=img.name; }} || exit 1
      echo Building factory image
      ${factoryImgScript { targetFiles=signedTargetFiles.name; img=img.name; out=factoryImg.name; }}
      ${pkgs.python3}/bin/python ${./generate_metadata.py} ${ota.name} > ${device}-${channel}
    ''; })));

    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    generateKeysScript = let
      keysToGenerate = [ "releasekey" "platform" "shared" "media" ]
                        ++ (optional (avbMode == "verity_only") "verity")
                        ++ (optionals (androidVersion == "10") [ "networkstack" ] ++ apex.packageNames);
      avbKeysToGenerate = apex.packageNames;
    in mkDefault (pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      for key in ${toString keysToGenerate}; do
        # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
        ! make_key "$key" "$1" || exit 1
      done

      ${optionalString (avbMode == "verity_only") "generate_verity_key -convert verity.x509.pem verity_key || exit 1"}

      # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
      ${optionalString (avbMode != "verity_only") ''
        openssl genrsa -out avb.pem 2048 || exit 1
        avbtool extract_public_key --key avb.pem --output avb_pkmd.bin || exit 1
      ''}

      ${concatMapStringsSep "\n" (k: ''
        openssl genrsa -out ${k}.pem 4096 || exit 1
        avbtool extract_public_key --key ${k}.pem --output ${k}.avbpubkey || exit 1
      '') avbKeysToGenerate}
    '');
  };
}
