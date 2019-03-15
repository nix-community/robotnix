{
  pkgs ? import <nixpkgs> { config = { android_sdk.accept_license = true; allowUnfree = true; }; },
  device ? "payton",
  rom ? "lineage",
  rev ? "${rom}-16.0",
  opengappsVariant ? null,
  enableWireguard ? false,
  manifest ? "https://github.com/LineageOS/android.git",
  extraFlags ? "-g all,-darwin,-infra,-vts,-sts --no-repo-verify",
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
  } + /srcs.nix);
in stdenv.mkDerivation rec {
  name = "nixdroid-${rev}-${device}";
  srcs = repo2nix.sources;
  unpackPhase = repo2nix.unpackPhase;

  prePatch = ''
    # Find device tree
    boardConfig="$(ls "device/"*"/${device}/BoardConfig.mk")"
    deviceConfig="$(ls "device/"*"/${device}/device.mk")"
    if ! [ -f "$boardConfig" ]; then
      echo "Tree for device ${device} not found"
      exit 1
    fi

    ${lib.optionalString (opengappsVariant != null) ''
      # Opengapps
      (
        echo 'GAPPS_VARIANT := ${opengappsVariant}'
        echo '$(call inherit-product, vendor/opengapps/build/opengapps-packages.mk)'
      ) >> "$deviceConfig"
    ''}

    ${lib.optionalString enableWireguard ''
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
    brunch "${device}"

    EOF
  '';

  installPhase = ''
    mkdir -p "$out"
    cd "out/target/product/${device}/"
    # copy regular image + md5sum
    cp -v "${rev}-"*"-UNOFFICIAL-${device}.zip"* "$out/"
    # ota file
    cp -v "${rom}_${device}-ota"*".zip" "$out/"
    ${lib.optionalString savePartitionImages ''
      mkdir -p "$out/misc"
      # partition images
      cp -v *.img kernel "$out/misc/"
    ''}
  '';

  fixupPhase = ":";
  configurePhase = ":";
}
