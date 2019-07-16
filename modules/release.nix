{ config, pkgs, lib, ... }:

with lib;
let
  signBuild = true;

  avbMode = {
    marlin = "verity_only";
    taimen = "vbmeta_simple";
    crosshatch = "vbmeta_chained";
  }.${config.deviceFamily};
  avbFlags = {
    verity_only = "--replace_verity_public_key $KEYSTOREPATH/verity_key.pub --replace_verity_private_key $KEYSTOREPATH/verity --replace_verity_keyid $KEYSTOREPATH/verity.x509.pem";
    vbmeta_simple = "--avb_vbmeta_key $KEYSTOREPATH/avb.pem --avb_vbmeta_algorithm SHA256_RSA2048";
    vbmeta_chained = "--avb_vbmeta_key $KEYSTOREPATH/avb.pem --avb_vbmeta_algortihm SHA256_RSA2048 --avb_system_key $KEYSTOREPATH/avb.pem --avb_system_algorithm SHA256_RSA2048";
  }.${avbMode};

  # Signing target files fails in signapk.jar with error -6 unless using this jdk
  jdk =  pkgs.callPackage <nixpkgs/pkgs/development/compilers/openjdk/8.nix> {
    bootjdk = pkgs.callPackage <nixpkgs/pkgs/development/compilers/openjdk/bootstrap.nix> { version = "8"; };
    inherit (pkgs.gnome2) GConf gnome_vfs;
    minimal = true;
  };

  buildTools = pkgs.stdenv.mkDerivation {
    name = "android-build-tools-${config.buildID}";
    src = config.source.dirs."build/make";
    nativeBuildInputs = with pkgs; [ python ];
    postPatch = ''
      substituteInPlace ./tools/releasetools/common.py \
        --replace "out/host/linux-x86" "${config.build.hostTools}" \
        --replace "java_path = \"java\"" "java_path = \"${jdk}/bin/java\""
      substituteInPlace ./tools/releasetools/build_image.py \
        --replace "system/extras/verity/build_verity_metadata.py" "$out/build_verity_metadata.py"
    '';
    installPhase = ''
      mkdir -p $out
      cp --reflink=auto -r ./tools/* $out
      cp --reflink=auto ${config.source.dirs."system/extras"}/verity/{build_verity_metadata.py,boot_signer,verity_signer} $out # Some extra random utilities from elsewhere
    '';
  };

  # Get a bunch of utilities to generate keys
  keyTools = pkgs.runCommandCC "android-key-tools-${config.buildID}" { nativeBuildInputs = with pkgs; [ python pkgconfig ]; buildInputs = with pkgs; [ boringssl ]; } ''
    mkdir -p $out/bin

    cp ${config.source.dirs."development"}/tools/make_key $out/bin/make_key
    substituteInPlace $out/bin/make_key --replace openssl ${getBin pkgs.openssl}/bin/openssl

    cc -o $out/bin/generate_verity_key \
      ${config.source.dirs."system/extras"}/verity/generate_verity_key.c \
      ${config.source.dirs."system/core"}/libcrypto_utils/android_pubkey.c \
      -I ${config.source.dirs."system/core"}/libcrypto_utils/include/ \
      -I ${pkgs.boringssl}/include ${pkgs.boringssl}/lib/libssl.a ${pkgs.boringssl}/lib/libcrypto.a -lpthread

    cp ${config.source.dirs."external/avb"}/avbtool $out/bin/avbtool
    patchShebangs $out/bin
  '';
in
{
  # TODO: Do this in a temporary directory. It's ugly to make build dir and ./tmp/* dir gets cleared in these scripts too.
  config.build.releaseScript = pkgs.writeScript "release.sh" ''
    #!${pkgs.runtimeShell}

    export PATH=${config.build.hostTools}/bin:${pkgs.openssl}/bin:${pkgs.zip}/bin:${pkgs.unzip}/bin:${jdk}/bin:$PATH
    KEYSTOREPATH=$1
    PREVIOUS_BUILDID=$2

    # sign_target_files_apks.py and others below requires this directory to be here.
    mkdir -p build/target/product/
    ln -sf ${config.source.dirs."build/make"}/target/product/security build/target/product/security

    echo Signing target files
    ${buildTools}/releasetools/sign_target_files_apks.py ${optionalString signBuild "-o -d $KEYSTOREPATH ${avbFlags}"} ${config.build.android.out}/aosp_${config.device}-target_files-${config.buildID}.zip ${config.device}-target_files-${config.buildID}.zip || exit 1

    echo Building OTA zip
    ${buildTools}/releasetools/ota_from_target_files.py --block ${optionalString signBuild "-k $KEYSTOREPATH/releasekey"} ${config.device}-target_files-${config.buildID}.zip ${config.device}-ota_update-${config.buildID}.zip || exit 1

    echo Building incremental OTA zip
    if [[ ! -z "$PREVIOUS_BUILDID" ]]; then
      ${buildTools}/releasetools/ota_from_target_files.py --block ${optionalString signBuild "-k $KEYSTOREPATH/releasekey"} -i ${config.device}-target_files-$PREVIOUS_BUILDID.zip ${config.device}-target_files-${config.buildID}.zip ${config.device}-incremental-$PREVIOUS_BUILDID-${config.buildID}.zip || exit 1
    fi

    echo Building .img file
    ${buildTools}/releasetools/img_from_target_files.py ${config.device}-target_files-${config.buildID}.zip ${config.device}-img-${config.buildID}.zip || exit 1

    export DEVICE=${config.device};
    export PRODUCT=${config.device};
    export BUILD=${config.buildID};
    export VERSION=${toLower config.buildID};

    # TODO: What if we don't have vendor.files?
    get_radio_image() {
      grep -Po "require version-$1=\K.+" ${config.vendor.files}/vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
    }
    export BOOTLOADER=$(get_radio_image bootloader google_devices/$DEVICE)
    export RADIO=$(get_radio_image baseband google_devices/$DEVICE)

    echo Building factory image
    ${pkgs.runtimeShell} ${config.source.dirs."device/common"}/generate-factory-images-common.sh

    rm -r build # Unsafe?

    ${pkgs.python3}/bin/python ${../generate_metadata.py} ${config.device}-ota_update-${config.buildID}.zip
  '';

  # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
  config.build.generateKeysScript = pkgs.writeScript "generate_keys.sh" ''
    #!${pkgs.runtimeShell}

    export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

    for key in {releasekey,platform,shared,media,verity,avb}; do
      # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
      ! make_key "$key" "$1" || exit 1
    done

    # Generate both verity and AVB keys. While not strictly necessary, I don't
    # see any harm in doing so--and the user may want to use the same keys for
    # multiple devices supporting different AVB modes.
    generate_verity_key -convert verity.x509.pem verity_key || exit 1
    avbtool extract_public_key --key avb.pk8 --output avb_pkmd.bin || exit 1
  '';
}
