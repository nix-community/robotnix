{
  pkgs ? import <nixpkgs> { config = { android_sdk.accept_license = true; allowUnfree = true; }; },
  device, rev, manifest, localManifests,
  buildID ? "nixdroid", # Preferably match the upstream vendor buildID
  buildType ? "user", # one of "user" "eng" "userdebug"
  additionalProductPackages ? [],
  vendorImg ? null,
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

# Trying to support pixel (xl) 1-3 devices.

let
  nixdroid-env = callPackage ./buildenv.nix {};
  repo2nix = import (import ./repo2nix.nix {
    inherit device manifest localManifests rev extraFlags;
    sha256 = if (sha256 != null) then sha256 else readFile sha256Path;
  });
  signBuild = (keyStorePath != null);
  flex = callPackage ./flex-2.5.39.nix {};
  avbMode = {
    marlin = "verity_only";
    sailfish = "verity_only";
    taimen = "vbmeta_simple";
    walleye = "vbmeta_simple";
    crosshatch = "vbmeta_chained";
    blueline = "vbmeta_chained";
  }.${device};
  avbFlags = {
    verity_only = "--replace_verity_public_key ${keyStorePath}/verity_key.pub --replace_verity_private_key ${keyStorePath}/verity --replace_verity_keyid" "${keyStorePath}/verity.x509.pem";
    vbmeta_simple = "--avb_vbmeta_key ${keyStorePath}/avb.pem --avb_vbmeta_algorithm SHA256_RSA2048";
    vbmeta_chained = "--avb_vbmeta_key ${keyStorePath}/avb.pem --avb_vbmeta_algortihm SHA256_RSA2048 --avb_system_key ${keyStorePath}/avb.pem --avb_system_algorithm SHA256_RSA2048";
  }.${avbMode};
in rec {
  # Hacky way to get an individual source dir from repo2nix.
  sourceDir = dirName: lib.findFirst (s: lib.hasSuffix ("-" + (builtins.replaceStrings ["/"] ["="] dirName)) s.outPath) null repo2nix.sources;
  vendorFiles = callPackage ./android-prepare-vendor {
    inherit device;
    img = vendorImg;
  };
  # Use NoCC here so we don't get extra environment variables that might conflict with AOSP build stuff. Like CC, NM, etc.
  androidBuild = stdenvNoCC.mkDerivation rec {
    name = "nixdroid-${rev}-${device}";
    srcs = repo2nix.sources;

    outputs = [ "out" "bin" ]; # This derivation builds AOSP release tools and target-files

    unpackPhase = ''
      ${optionalString usePatchedCoreutils "export PATH=${callPackage ./misc/coreutils.nix {}}/bin/:$PATH"}
      echo $PATH
      ${repo2nix.unpackPhase}
    '' + optionalString (vendorImg != null) "cp --reflink=auto -r ${vendorFiles}/* .";

    # Fix a locale issue with included flex program
    #mkdir -p packages/apps/F-Droid/app/build/outputs/apk/full/release/
    #cp ${fdroidPrivExtApk} packages/apps/F-Droid/app/build/outputs/apk/full/release/app-full-release-unsigned.apk
    postPatch = ''
      ln -sf ${flex}/bin/flex prebuilts/misc/linux-x86/flex/flex-2.5.39

      substituteInPlace device/google/marlin/aosp_marlin.mk --replace "PRODUCT_MODEL := AOSP on msm8996" "PRODUCT_MODEL := Pixel XL@"
      substituteInPlace  device/google/marlin/aosp_marlin.mk --replace "PRODUCT_MANUFACTURER := google" "PRODUCT_MANUFACTURER := Google"
      substituteInPlace device/google/marlin/aosp_sailfish.mk --replace "PRODUCT_MODEL := AOSP on msm8996" "PRODUCT_MODEL := Pixel"
      substituteInPlace device/google/marlin/aosp_sailfish.mk --replace "PRODUCT_MANUFACTURER := google" "PRODUCT_MANUFACTURER := Google"

      substituteInPlace device/google/taimen/aosp_taimen.mk --replace "PRODUCT_MODEL := AOSP on taimen" "PRODUCT_MODEL := Pixel 2 XL"
      substituteInPlace device/google/muskie/aosp_walleye.mk --replace "PRODUCT_MODEL := AOSP on walleye" "PRODUCT_MODEL := Pixel 2"

      substituteInPlace device/google/crosshatch/aosp_crosshatch.mk --replace "PRODUCT_MODEL := AOSP on crosshatch" "PRODUCT_MODEL := Pixel 3 XL"
      substituteInPlace device/google/crosshatch/aosp_blueline.mk --replace "PRODUCT_MODEL := AOSP on blueline" "PRODUCT_MODEL := Pixel 3"

      substituteInPlace packages/apps/F-DroidPrivilegedExtension/app/src/main/java/org/fdroid/fdroid/privileged/PrivilegedService.java \
        --replace BuildConfig.APPLICATION_ID "\"org.fdroid.fdroid.privileged\""
    '' + concatMapStringsSep "\n" (name: "echo PRODUCT_PACKAGES += ${name} >> build/make/target/product/core.mk") additionalProductPackages;

    ANDROID_JAVA_HOME="${pkgs.jdk.home}";
    BUILD_NUMBER=buildID;
    DISPLAY_BUILD_NUMBER="true";
    ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G";

    # Alternative is to just "make target-files-package brillo_update_payload
    # Parts from https://github.com/GrapheneOS/script/blob/pie/release.sh
    buildPhase = ''
      cat << 'EOF' | ${nixdroid-env}/bin/nixdroid-build
      source build/envsetup.sh
      choosecombo release "aosp_${device}" ${buildType}
      make otatools-package target-files-package dist
      EOF
    '';

    # Kinda ugly to just throw all this in $bin/
    # Don't do patchelf in this derivation, just in case it fails we'd still like to have cached results
    installPhase = ''
      mkdir -p $out $bin
      cp --reflink=auto -r out/target/product/${device}/obj/PACKAGING/target_files_intermediates/aosp_${device}-target_files-${buildID}.zip $out/
      cp --reflink=auto -r out/host/linux-x86/{bin,lib,lib64,usr,framework} $bin/
    '';

    configurePhase = ":";
    dontMoveLib64 = true;
  };

  # TODO: Any reason to use nixpkgs kernel stuff?
  marlinKernel = stdenvNoCC.mkDerivation {
    name = "kernel-marlin-${rev}";
    src = builtins.fetchGit {
      url = "https://android.googlesource.com/kernel/msm";
      # Have to use ref = $shortrev... since rev in builtins.fetchGit requires full revision length.
      ref = "android-9.0.0_r0.74"; # branch: android-msm-marlin-3.18-pie-qpr3
  #    ref = import (runCommand "marlinKernelRev" {} ''
  #        shortrev=$(grep -a 'Linux version' ${sourceDir "device/google/marlin-kernel"}/.prebuilt_info/kernel/prebuilt_info_Image_lz4-dtb.asciipb | cut -d " " -f 6 | cut -d '-' -f 2 | sed 's/^g//g')
  #        echo \"$shortrev\" > $out
  #      '');
    };

    prePatch = lib.optionalString (keyStorePath != null) "cp ${keyStorePath}/verity_user.der.x509 .";

    buildPhase = ''
      make ARCH=arm64 marlin_defconfig
      make CONFIG_COMPAT_VDSO=n CROSS_COMPILE=${sourceDir "prebuilts/gcc"}/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-;
    '';

    installPhase = ''
      mkdir -p $out
      cp arch/arm64/boot/Image.lz4-dtb $out
    '';
  };

  # Tools that were built for the host in the process of building the target files.
  # Do the patchShebangs / patchelf stuff in this derivation so it failing for any reason doesn't stop the main androidBuild
  androidHostTools = stdenv.mkDerivation {
    name = "android-host-tools-${rev}";
    src = androidBuild.bin;
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ python ncurses5 ]; # One of the utilities needs libncurses.so.5 but it's not in the lib/ dir of the androidBuild files.
    installPhase = ''
      mkdir -p $out
      cp --reflink=auto -r * $out
    '';
    dontMoveLib64 = true;
  };

  jdk =  pkgs.callPackage <nixpkgs/pkgs/development/compilers/openjdk/8.nix> {
    bootjdk = pkgs.callPackage <nixpkgs/pkgs/development/compilers/openjdk/bootstrap.nix> { version = "8"; };
    inherit (pkgs.gnome2) GConf gnome_vfs;
    minimal = true;
  };
  buildTools = stdenv.mkDerivation {
    name = "android-build-tools-${rev}";
    src = sourceDir "build/make";
    nativeBuildInputs = [ python ];
    postPatch = ''
      substituteInPlace ./tools/releasetools/common.py \
        --replace "out/host/linux-x86" "${androidHostTools}" \
        --replace "java_path = \"java\"" "java_path = \"${jdk}/bin/java\""
      substituteInPlace ./tools/releasetools/build_image.py \
        --replace "system/extras/verity/build_verity_metadata.py" "$out/build_verity_metadata.py"
    '';
    installPhase = ''
      mkdir -p $out
      cp --reflink=auto -r ./tools/* $out
      cp --reflink=auto ${sourceDir "system/extras"}/verity/{build_verity_metadata.py,boot_signer,verity_signer} $out # Some extra random utilities from elsewhere
    '';
  };

  # Make this into a script that can be run outside of nixpkgs
  signedTargetFiles = runCommand "${device}-signed_target_files-${buildID}.zip" { nativeBuildInputs = [ androidHostTools openssl pkgs.zip unzip jdk ]; } ''
    mkdir -p build/target/product/
    ln -s ${sourceDir "build/make"}/target/product/security build/target/product/security # Make sure it can access the default keys if needed
    ${buildTools}/releasetools/sign_target_files_apks.py ${optionalString signBuild "-o -d ${keyStorePath} ${avbFlags}"} ${androidBuild.out}/aosp_${device}-target_files-${buildID}.zip $out
  '';
  ota = runCommand "${device}-ota_update-${buildID}.zip" { nativeBuildInputs = [ androidHostTools openssl pkgs.zip unzip jdk ]; } ''
    mkdir -p build/target/product/
    ln -s ${sourceDir "build/make"}/target/product/security build/target/product/security # Make sure it can access the default keys if needed
    ${buildTools}/releasetools/ota_from_target_files.py ${optionalString signBuild "-k ${keyStorePath}/releasekey"} ${signedTargetFiles} $out
  '';
  img = runCommand "${device}-img-${buildID}.zip" { nativeBuildInputs = [ androidHostTools openssl pkgs.zip unzip jdk ]; }
    "${buildTools}/releasetools/img_from_target_files.py ${signedTargetFiles} $out";
  factoryImg = runCommand "${device}-${toLower buildID}-factory.zip" { nativeBuildInputs = [ pkgs.zip unzip ]; } ''
      DEVICE=${device};
      PRODUCT=${device};
      BUILD=${buildID};
      VERSION=${toLower buildID};

      get_radio_image() {
        grep -Po "require version-$1=\K.+" ${vendorFiles}/vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
      }
      BOOTLOADER=$(get_radio_image bootloader google_devices/$DEVICE)
      RADIO=$(get_radio_image baseband google_devices/$DEVICE)

      ln -s ${signedTargetFiles} $PRODUCT-target_files-$BUILD.zip
      ln -s ${img} $PRODUCT-img-$BUILD.zip

      source ${sourceDir "device/common"}/generate-factory-images-common.sh
      cp --reflink=auto ${device}-${toLower buildID}-*.zip $out
    '';
}

# Update with just img using: fastboot -w update <...>.img
