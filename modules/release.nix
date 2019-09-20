{ config, pkgs, lib, ... }:

with lib;
let
  nixdroid-env = pkgs.callPackage ../buildenv.nix {};

  avbFlags = {
    verity_only = "--replace_verity_public_key $KEYSDIR/verity_key.pub --replace_verity_private_key $KEYSDIR/verity --replace_verity_keyid $KEYSDIR/verity.x509.pem";
    vbmeta_simple = "--avb_vbmeta_key $KEYSDIR/avb.pem --avb_vbmeta_algorithm SHA256_RSA2048";
    vbmeta_chained = "--avb_vbmeta_key $KEYSDIR/avb.pem --avb_vbmeta_algorithm SHA256_RSA2048 --avb_system_key $KEYSDIR/avb.pem --avb_system_algorithm SHA256_RSA2048";
  }.${config.avbMode};

  # Signing target files fails in signapk.jar with error -6 unless using this jdk
  jdk = pkgs.callPackage (pkgs.path + /pkgs/development/compilers/openjdk/8.nix) {
    bootjdk = pkgs.callPackage (pkgs.path + /pkgs/development/compilers/openjdk/bootstrap.nix) { version = "8"; };
    inherit (pkgs.gnome2) GConf gnome_vfs;
    minimal = true;
  };

  buildTools = pkgs.stdenv.mkDerivation {
    name = "android-build-tools-${config.buildNumber}";
    src = config.source.dirs."build/make".contents;
    buildInputs = with pkgs; [ python ];
    patches = [ (pkgs.substituteAll {
      src = (../patches + "/${config.androidVersion}" + /buildtools.patch);
      java = "${jdk}/bin/java";
      search_path = config.build.hostTools;
    }) ];
    installPhase = ''
      mkdir -p $out
      cp --reflink=auto -r ./tools/* $out
      cp --reflink=auto ${config.source.dirs."system/extras".contents}/verity/{build_verity_metadata.py,boot_signer,verity_signer} $out # Some extra random utilities from elsewhere
    '';
  };

  # Get a bunch of utilities to generate keys
  keyTools = pkgs.runCommandCC "android-key-tools-${config.buildNumber}" { buildInputs = with pkgs; [ python pkgconfig boringssl ]; } ''
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
    export PATH=${config.build.hostTools}/bin:${pkgs.openssl}/bin:${pkgs.zip}/bin:${pkgs.unzip}/bin:${jdk}/bin:${pkgs.getopt}/bin:${pkgs.hexdump}/bin:${pkgs.perl}/bin:${pkgs.toybox}/bin:$PATH

    # sign_target_files_apks.py and others require this directory to be here.
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

  unsignedTargetFiles = config.build.android + "/aosp_${config.device}-target_files-${config.buildNumber}.zip";
  signedTargetFilesScript = { out }:
    ''${buildTools}/releasetools/sign_target_files_apks.py ''${KEYSDIR:+-o -d $KEYSDIR ${avbFlags}} ${unsignedTargetFiles} ${out}'';
  otaScript = { targetFiles, prevTargetFiles ? null, out }:
    ''${buildTools}/releasetools/ota_from_target_files.py --block ''${KEYSDIR:+-k $KEYSDIR/releasekey} ${optionalString (prevTargetFiles != null) "-i ${prevTargetFiles}"} ${targetFiles} ${out}'';
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

  targetFiles = if config.signBuild then signedTargetFiles else unsignedTargetFiles;
  signedTargetFiles = runWrappedCommand "signed_target_files" signedTargetFilesScript {};
  ota = runWrappedCommand "ota_update" otaScript { inherit targetFiles; };
  incrementalOta = runWrappedCommand "incremental-${config.prevBuildNumber}" otaScript { inherit targetFiles; prevTargetFiles=config.prevTargetFiles; };
  img = runWrappedCommand "img" imgScript { inherit targetFiles; };
  factoryImg = runWrappedCommand "factory" factoryImgScript { inherit targetFiles; img=config.build.img; };
in
{
  options = {
    incremental = mkOption {
      default = false;
      type = types.bool;
      description = "Whether to include an incremental build in config.build.otaDir";
    };

    channel = mkOption {
      default = "stable";
      type = types.strMatching "(stable|beta)";
      description = "Default channel to use for updates (can be modified in app)";
    };

    prevBuildDir = mkOption {
      type = types.str;
    };

    prevBuildNumber = mkOption {
      type = types.str;
    };

    prevTargetFiles = mkOption {
      type = types.path;
    };
  };

  config.prevBuildNumber = let
      metadata = builtins.readFile (config.prevBuildDir + "/${config.device}-${config.channel}");
    in mkDefault (head (splitString " " metadata));
  config.prevTargetFiles = mkDefault (config.prevBuildDir + "/${config.device}-target_files-${config.prevBuildNumber}");

  config.build = {
    # These can be used to build these products inside nix. Requires putting the secret keys under /keys in the sandbox
    inherit signedTargetFiles ota incrementalOta img factoryImg;

    otaMetadata = pkgs.runCommand "${config.device}-${config.channel}" {} ''
      ${pkgs.python3}/bin/python ${./generate_metadata.py} ${config.build.ota} > $out
    '';

    # TODO: target-files aren't necessary to publish--but are useful to include if prevBuildDir is set to otaDir output
    otaDir = pkgs.linkFarm "${config.device}-otaDir" (
      (map (p: {name=p.name; path=p;}) (with config.build; [ ota otaMetadata ] ++ (optional config.incremental incrementalOta)))
      ++ [{ name="${config.device}-target_files-${config.buildNumber}.zip"; path=targetFiles; }]
    );

    # TODO: Do this in a temporary directory. It's ugly to make build dir and ./tmp/* dir gets cleared in these scripts too.
    # Maybe just remove this script? It's definitely complicated--and often untested
    releaseScript = pkgs.writeScript "release.sh" (''
      #!${pkgs.runtimeShell}
      export PREV_BUILDNUMBER=$2
      '' + (wrapScript { keysDir="$1"; commands=''
      if [[ "$KEYSDIR" ]]; then
        echo Signing target files
        ${signedTargetFilesScript { out=signedTargetFiles.name; }} || exit 1
      fi
      echo Building OTA zip
      ${otaScript { targetFiles=signedTargetFiles.name; out=ota.name; }} || exit 1
      echo Building incremental OTA zip
      if [[ ! -z "$PREV_BUILDNUMBER" ]]; then
        ${otaScript {
          targetFiles=signedTargetFiles.name;
          prevTargetFiles="${config.device}-target_files-$PREV_BUILDNUMBER.zip";
          out="${config.device}-incremental-$PREV_BUILDNUMBER-${config.buildNumber}.zip";
        }} || exit 1
      fi
      echo Building .img file
      ${imgScript { targetFiles=signedTargetFiles.name; out=img.name; }} || exit 1
      echo Building factory image
      ${factoryImgScript { targetFiles=signedTargetFiles.name; img=img.name; out=factoryImg.name; }}
      ${pkgs.python3}/bin/python ${./generate_metadata.py} ${ota.name} > ${config.device}-${config.channel}
    ''; }));

    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    generateKeysScript = let
      keysToGenerate = [ "releasekey" "platform" "shared" "media" ]
                        ++ (optional (config.avbMode == "verity_only") "verity")
                        ++ (optional (config.androidVersion == "10") "networkstack");
    in pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      for key in ${toString keysToGenerate}; do
        # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
        ! make_key "$key" "$1" || exit 1
      done

      ${optionalString (config.avbMode == "verity_only") "generate_verity_key -convert verity.x509.pem verity_key || exit 1"}
      ${optionalString (config.avbMode != "verity_only") ''
        openssl genrsa -out avb.pem 2048 || exit 1
        avbtool extract_public_key --key avb.pem --output avb_pkmd.bin || exit 1
      ''}
    '';
  };
}
