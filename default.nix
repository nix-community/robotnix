{
  pkgs ? import <nixpkgs> { config = { android_sdk.accept_license = true; allowUnfree = true; }; },
  device ? "payton",
  rom ? "lineage",
  rev ? "${rom}-16.0",
  opengappsVariant ? null,
  keyStorePath ? null,
  enableWireguard ? false,
  manifest ? "https://github.com/LineageOS/android.git",
  extraFlags ? "-g all,-darwin,-infra,-sts --no-repo-verify",
  sha256 ? "0iqjqi2vwi6lfrk0034fdb1v8927g0vak2qanljw6hvcad0fid6r",
  savePartitionImages ? false
}:

with pkgs; with lib;
let
  nixdroid-env = callPackage ./buildenv.nix {};
  repo2nix = import (import ./repo2nix.nix {
    inherit manifest rev extraFlags sha256;
    name = "nixdroid-${rev}-${device}";
    localManifests = flatten [
      (./roomservice- + "${device}.xml")
      (optional (opengappsVariant != null) [ ./opengapps.xml ])
      (optional enableWireguard [ ./wireguard.xml ])
    ];
  });
  signBuild = (keyStorePath != null);
in stdenv.mkDerivation rec {
  name = "nixdroid-${rev}-${device}";
  srcs = repo2nix.sources;
  unpackPhase = ''
    ${optionalString (builtins.hasAttr "coreutils-copy_file_read" pkgs) "export PATH=${pkgs.coreutils-copy_file_read}/bin/:$PATH"}
    ${repo2nix.unpackPhase}
  '';

  prePatch = ''
    # Find device tree
    boardConfig="$(ls "device/"*"/${device}/BoardConfig.mk")"
    deviceConfig="$(ls "device/"*"/${device}/device.mk")"
    if ! [ -f "$boardConfig" ]; then
      echo "Tree for device ${device} not found"
      exit 1
    fi

    ${optionalString (opengappsVariant != null) ''
      # Opengapps
      (
        echo 'GAPPS_VARIANT := ${opengappsVariant}'
        echo '$(call inherit-product, vendor/opengapps/build/opengapps-packages.mk)'
      ) >> "$deviceConfig"
    ''}

    ${optionalString enableWireguard ''
      # Wireguard
      kernelTree="$(grep 'TARGET_KERNEL_SOURCE := ' "$boardConfig" | cut -d' ' -f3)"
      wireguardHome="$kernelTree/net/wireguard"
      mkdir -p "$wireguardHome"
      mv wireguard/*/* "$wireguardHome"
      touch "$wireguardHome/.check"

      sed -i 's/tristate/bool/;s/default m/default y/;' "$wireguardHome/Kconfig"
    ''}
  '';


  buildPhase = ''
    cat << EOF | ${nixdroid-env}/bin/nixdroid-build
    export LANG=C
    export ANDROID_JAVA_HOME="${pkgs.jdk.home}"
    export DISPLAY_BUILD_NUMBER=true
    export ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G"
    # for jack
    export HOME="$PWD"
    export USER="$(id -un)"

    source build/envsetup.sh
    breakfast "${device}"
    mka otatools-package target-files-package dist
    # TODO: incremental (-i) OTA
    ${optionalString signBuild "cp -R ${keyStorePath} .keystore"}   # copy the keystore, because some of the scripts want to chmod etc.
    ./build/tools/releasetools/sign_target_files_apks.py ${optionalString signBuild "-o -d .keystore"} out/dist/*-target_files-*.zip signed-target_files.zip
    ./build/tools/releasetools/ota_from_target_files.py ${optionalString signBuild "-k .keystore/releasekey"} --backup=true signed-target_files.zip signed-ota_update.zip

EOF
  '';

  installPhase = ''
    mkdir -p "$out"/nix-support
    # ota file
    cp -v signed-ota_update.zip "$out/"
    ${optionalString savePartitionImages ''
      cd "out/target/product/${device}/"
      mkdir -p "$out/misc"
      # partition images
      cp -v *.img kernel "$out/misc/"
    ''}
    echo "file zip $out/signed-ota_update.zip" > $out/nix-support/hydra-build-products
  '';

  fixupPhase = ":";
  configurePhase = ":";
}
