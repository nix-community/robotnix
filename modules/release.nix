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

  # Use bash substitution to only set options if KEYSDIR is set
  signedTargetFilesScript = { out }: ''
    ${buildTools}/releasetools/sign_target_files_apks.py ''${KEYSDIR:+-o -d $KEYSDIR ${avbFlags}} ${config.build.android.out}/aosp_${config.device}-target_files-${config.buildNumber}.zip ${out} || exit 1
  '';

  otaScript = { signedTargetFiles, out }: ''
    ${buildTools}/releasetools/ota_from_target_files.py --block ''${KEYSDIR:+-k $KEYSDIR/releasekey} ${signedTargetFiles} ${out} || exit 1
  '';

  imgScript = { signedTargetFiles, out }: ''
    ${buildTools}/releasetools/img_from_target_files.py ${signedTargetFiles} ${out} || exit 1
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
in
{
  config.build = {
    # These can be used to build these products inside nix. Requires putting the secret keys under /keys in the sandbox
    # TODO: Currently can only build here with keys enabled
    signedTargetFiles = if config.signBuild
      then pkgs.runCommand "${config.device}-signed_target_files-${config.buildNumber}.zip" {}
      (wrapScript {
        commands = signedTargetFilesScript { out="$out"; };
        keysDir = optionalString config.signBuild "/keys/${config.device}";
      })
      else config.build.android + "/aosp_${config.device}-target_files-${config.buildNumber}.zip";
    ota = pkgs.runCommand "${config.device}-ota_update-${config.buildNumber}.zip" {}
      (wrapScript {
        commands = otaScript { signedTargetFiles=config.build.signedTargetFiles; out="$out"; };
        keysDir = optionalString config.signBuild "/keys/${config.device}";
      });
    img = pkgs.runCommand "${config.device}-img-${config.buildNumber}.zip" {}
      (wrapScript {
        commands = imgScript { signedTargetFiles=config.build.signedTargetFiles; out="$out"; };
      }); # No need for keys here
    otaMetadata = pkgs.runCommand "${config.device}-stable" {} ''
      ${pkgs.python3}/bin/python ${./generate_metadata.py} ${config.build.ota} > $out
    '';

    otaDir = pkgs.linkFarm "${config.device}-otaDir" (with config.build; [ { name=ota.name; path=ota; } { name=otaMetadata.name; path=otaMetadata;} ]);

    # TODO: Do this in a temporary directory. It's ugly to make build dir and ./tmp/* dir gets cleared in these scripts too.
    # Maybe just remove this script? It's definitely complicated--and often untested
    releaseScript = pkgs.writeScript "release.sh" (''
      #!${pkgs.runtimeShell}
      '' + (wrapScript { keysDir="$1"; commands=''
      PREV_BUILDNUMBER=$2

      echo Signing target files
      ${signedTargetFilesScript {
        out="${config.device}-target_files-${config.buildNumber}.zip";
      }}

      echo Building OTA zip
      ${otaScript {
        signedTargetFiles="${config.device}-target_files-${config.buildNumber}.zip";
        out="${config.device}-ota_update-${config.buildNumber}.zip";
      }}

      echo Building incremental OTA zip
      if [[ ! -z "$PREV_BUILDNUMBER" ]]; then
        ${buildTools}/releasetools/ota_from_target_files.py --block ''${KEYSDIR:+"-k $KEYSDIR/releasekey} -i ${config.device}-target_files-$PREV_BUILDNUMBER.zip ${config.device}-target_files-${config.buildNumber}.zip ${config.device}-incremental-$PREV_BUILDNUMBER-${config.buildNumber}.zip || exit 1
      fi

      echo Building .img file
      ${imgScript {
        signedTargetFiles="${config.device}-target_files-${config.buildNumber}.zip";
        out="${config.device}-img-${config.buildNumber}.zip";
      }}

      export DEVICE=${config.device};
      export PRODUCT=${config.device};
      export BUILD=${config.buildNumber};
      export VERSION=${toLower config.buildNumber};

      # TODO: What if we don't have vendor.files?
      get_radio_image() {
        grep -Po "require version-$1=\K.+" ${config.build.vendor.files}/vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
      }
      export BOOTLOADER=$(get_radio_image bootloader google_devices/$DEVICE)
      export RADIO=$(get_radio_image baseband google_devices/$DEVICE)

      echo Building factory image
      ${pkgs.runtimeShell} ${config.source.dirs."device/common".contents}/generate-factory-images-common.sh

      ${pkgs.python3}/bin/python ${./generate_metadata.py} ${config.device}-ota_update-${config.buildNumber}.zip > ${config.device}-stable
    ''; }));

    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    generateKeysScript = pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      for key in {releasekey,platform,shared,media${optionalString (config.avbMode == "verity_only") ",verity"}}; do
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
