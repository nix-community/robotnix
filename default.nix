{
  pkgs ? import <nixpkgs> { config = { android_sdk.accept_license = true; allowUnfree = true; }; },
  device, rev, manifest, localManifests, otaURL,
  opengappsVariant ? null,
  enableWireguard ? false,
  keyStorePath ? null,
  extraFlags ? "--no-repo-verify",
  sha256 ? null,
  sha256Path ? null,
  savePartitionImages ? false,
  usePatchedCoreutils ? false,
  romtype ? "NIGHTLY"  # one of RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL
}:
with pkgs; with lib;

let
  nixdroid-env = callPackage ./buildenv.nix {};
  repo2nix = import (import ./repo2nix.nix {
    inherit device manifest localManifests rev extraFlags;
    sha256 = if (sha256 != null) then sha256 else readFile sha256Path;
  });
  signBuild = (keyStorePath != null);
  otaZipFileName = "signed-ota_update.zip";
  json = { response = [ {
    datetime = "DATE_HERE";
    filename = otaZipFileName;
    id = "ID_HERE";
    romtype = romtype;
    size = "SIZE_HERE";  # this is (probably) vendor specific
    url = otaURL + otaZipFileName;
    version = "VERSION_HERE";  # this is definitely vendor specific
  } ]; }; # TBH, this whole updater thing is different from ROM to ROM
in { ota = stdenv.mkDerivation rec {
  name = "nixdroid-${rev}-${device}";
  srcs = repo2nix.sources;
  unpackPhase = ''
    ${optionalString usePatchedCoreutils "export PATH=${callPackage ./misc/coreutils.nix {}}/bin/:$PATH"}
    echo $PATH
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

    # insert updater url property before last line into buildinfo.sh
    sed -i '$iecho "lineage.updater.uri=${otaURL}"' build/tools/buildinfo.sh
  '';


  buildPhase = ''
    cat << 'EOF' | ${nixdroid-env}/bin/nixdroid-build
    export LANG=C
    export ANDROID_JAVA_HOME="${pkgs.jdk.home}"
    export DISPLAY_BUILD_NUMBER=true
    export ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G"
    # for jack
    export HOME="$PWD"
    export USER="$(id -un)"
    export RELEASE_TYPE="${romtype}"  # FIXME: does this work on non-lineage roms?

    source build/envsetup.sh
    breakfast "${device}"
    mka otatools-package target-files-package dist
    # TODO: incremental (-i) OTA
    ${optionalString signBuild "cp -R ${keyStorePath} .keystore"}   # copy the keystore, because some of the scripts want to chmod etc.
    ./build/tools/releasetools/sign_target_files_apks.py ${optionalString signBuild "-o -d .keystore"} out/dist/*-target_files-*.zip signed-target_files.zip
    ./build/tools/releasetools/ota_from_target_files.py ${optionalString signBuild "-k .keystore/releasekey"} --backup=true signed-target_files.zip ${otaZipFileName}

    EOF
  '';

  installPhase = ''
    mkdir -p "$out"/nix-support

    # ota json
    echo '${builtins.toJSON json}' > $out/json
    substituteInPlace $out/json \
      --replace DATE_HERE $(date +%s) \
      --replace SIZE_HERE $(du ${otaZipFileName} | cut -d$'\t' -f 1) \
      --replace ID_HERE $(sha256sum ${otaZipFileName} | cut -d " " -f 1) \
      --replace VERSION_HERE $(cut -d "-" -f 2 <<< ${rev})

    # ota zip
    cp -v ${otaZipFileName} "$out/"
    ${optionalString savePartitionImages ''
      cd "out/target/product/${device}/"
      mkdir -p "$out/misc"
      # partition images
      cp -v *.img kernel "$out/misc/"
    ''}
    echo "file zip $out/${otaZipFileName}" > $out/nix-support/hydra-build-products
    echo "file json $out/json" >> $out/nix-support/hydra-build-products

  '';

  fixupPhase = ":";
  configurePhase = ":";
};}
