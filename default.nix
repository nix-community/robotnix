{
  pkgs ? import <nixpkgs> { config = { android_sdk.accept_license = true; allowUnfree = true; }; },
  device, rev, manifest, localManifests,
  buildID ? "nixdroid", # Preferably relate to the upstream vendor buildID
  buildType ? "user", # one of "user" "eng" "userdebug"
  additionalProductPackages ? [], # A list of strings denoting product packages that should be included in build
  removedProductPackages ? [], # A list of strings denoting product packages that should be removed from default build
  vendorImg ? null,
  msmKernelRev ? null,
  verityx509 ? null,
  opengappsVariant ? null,
  enableWireguard ? false,
  extraFlags ? "--no-repo-verify",
  sha256 ? null,
  sha256Path ? null,
  savePartitionImages ? false,
  usePatchedCoreutils ? false,
}:
with pkgs; with lib;

# Trying to support pixel (xl) 1-3 devices.

let
  nixdroid-env = callPackage ./buildenv.nix {};
  repo2nix = import (import ./repo2nix.nix {
    inherit device manifest localManifests rev extraFlags;
    sha256 = if (sha256 != null) then sha256 else readFile sha256Path;
  });
  flex = callPackage ./flex-2.5.39.nix {};
  deviceFamily = {
    marlin = "marlin"; # Pixel XL
    sailfish = "marlin"; # Pixel
    taimen = "taimen"; # Pixel 2 XL
    walleye = "taimen"; # Pixel 2
    crosshatch = "crosshatch"; # Pixel 3 XL
    blueline = "crosshatch"; # Pixel 3
  }.${device};
  kernelConfigName = {
    marlin = "marlin";
    taimen = "wahoo";
    crosshatch = "b1c1";
  }.${deviceFamily};
  avbMode = {
    marlin = "verity_only";
    taimen = "vbmeta_simple";
    crosshatch = "vbmeta_chained";
  }.${deviceFamily};
  avbFlags = {
    verity_only = "--replace_verity_public_key $KEYSTOREPATH/verity_key.pub --replace_verity_private_key $KEYSTOREPATH/verity --replace_verity_keyid $KEYSTOREPATH/verity.x509.pem";
    vbmeta_simple = "--avb_vbmeta_key $KEYSTOREPATH/avb.pem --avb_vbmeta_algorithm SHA256_RSA2048";
    vbmeta_chained = "--avb_vbmeta_key $KEYSTOREPATH/avb.pem --avb_vbmeta_algortihm SHA256_RSA2048 --avb_system_key $KEYSTOREPATH/avb.pem --avb_system_algorithm SHA256_RSA2048";
  }.${avbMode};
  signBuild = (deviceFamily == "marlin" && verityx509 != null);
  # TODO: Maybe just always rebuild kernel? What's the harm?
  useCustomKernel = (deviceFamily == "marlin" && signBuild) || enableWireguard;
in rec {
  # Hacky way to get an individual source dir from repo2nix.
  sourceDir = dirName: lib.findFirst (s: lib.hasSuffix ("-" + (builtins.replaceStrings ["/"] ["="] dirName)) s.outPath) null repo2nix.sources;
  vendorFiles = callPackage ./android-prepare-vendor {
    inherit device;
    img = vendorImg;
  };
  # TODO: Move this out into a "chromium" webview module
  config_webview_packages = writeText "config_webview_packages.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <webviewproviders>
      <webviewprovider description="Chromium" packageName="org.chromium.chrome" availableByDefault="true">
      </webviewprovider>
    </webviewproviders>
  '';
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

      substituteInPlace device/google/marlin/aosp_marlin.mk --replace "PRODUCT_MODEL := AOSP on msm8996" "PRODUCT_MODEL := Pixel XL"
      substituteInPlace device/google/marlin/aosp_marlin.mk --replace "PRODUCT_MANUFACTURER := google" "PRODUCT_MANUFACTURER := Google"
      substituteInPlace device/google/marlin/aosp_sailfish.mk --replace "PRODUCT_MODEL := AOSP on msm8996" "PRODUCT_MODEL := Pixel"
      substituteInPlace device/google/marlin/aosp_sailfish.mk --replace "PRODUCT_MANUFACTURER := google" "PRODUCT_MANUFACTURER := Google"

      substituteInPlace device/google/taimen/aosp_taimen.mk --replace "PRODUCT_MODEL := AOSP on taimen" "PRODUCT_MODEL := Pixel 2 XL"
      substituteInPlace device/google/muskie/aosp_walleye.mk --replace "PRODUCT_MODEL := AOSP on walleye" "PRODUCT_MODEL := Pixel 2"

      substituteInPlace device/google/crosshatch/aosp_crosshatch.mk --replace "PRODUCT_MODEL := AOSP on crosshatch" "PRODUCT_MODEL := Pixel 3 XL"
      substituteInPlace device/google/crosshatch/aosp_blueline.mk --replace "PRODUCT_MODEL := AOSP on blueline" "PRODUCT_MODEL := Pixel 3"

      substituteInPlace packages/apps/F-DroidPrivilegedExtension/app/src/main/java/org/fdroid/fdroid/privileged/PrivilegedService.java \
        --replace BuildConfig.APPLICATION_ID "\"org.fdroid.fdroid.privileged\""

      #cp ${config_webview_packages} frameworks/base/core/res/res/xml/config_webview_packages.xml

      # disable QuickSearchBox widget on home screen
      substituteInPlace packages/apps/Launcher3/src/com/android/launcher3/config/BaseFlags.java \
        --replace "QSB_ON_FIRST_SCREEN = true;" "QSB_ON_FIRST_SCREEN = false;"
      # fix compile error with uninitialized variable
      substituteInPlace packages/apps/Launcher3/src/com/android/launcher3/provider/ImportDataTask.java \
        --replace "boolean createEmptyRowOnFirstScreen;" "boolean createEmptyRowOnFirstScreen = false;"

      ${concatMapStringsSep "\n" (name: "echo PRODUCT_PACKAGES += ${name} >> build/make/target/product/core.mk") additionalProductPackages}
      ${concatMapStringsSep "\n" (name: "sed -i '/${name} \\\\/d' build/make/target/product/*.mk") removedProductPackages}
      '';
    # TODO: The " \\" in the above sed is a bit flaky, and would require the line to end in " \\"
    # come up with something more robust.

    ANDROID_JAVA_HOME="${pkgs.jdk.home}";
    BUILD_NUMBER=buildID;
    DISPLAY_BUILD_NUMBER="true";
    ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G";

    # Alternative is to just "make target-files-package brillo_update_payload
    # Parts from https://github.com/GrapheneOS/script/blob/pie/release.sh
    buildPhase = ''
      cat << 'EOF' | ${nixdroid-env}/bin/nixdroid-build
      source build/envsetup.sh
      ${optionalString useCustomKernel
        "export TARGET_PREBUILT_KERNEL=${customKernel}/Image.lz4-dtb" }
      choosecombo release "aosp_${device}" ${buildType}
      make otatools-package target-files-package
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

  prebuiltGCC = stdenv.mkDerivation {
    name = "prebuilt-gcc";
    src = sourceDir "prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"; # TODO: Check that this path is in each pixel tree
    nativeBuildInputs = [ python autoPatchelfHook ];
    installPhase = ''
      cp -r $src $out
    '';
  };

  # TODO: Could just use the version in nixpkgs?
  wireguardsrc = fetchzip {
    url = "https://git.zx2c4.com/WireGuard/snapshot/WireGuard-0.0.20190406.tar.xz";
    sha256 = "1rqyyyx7j41vpp4jigagqs2qdyfngh15y48ghdqfrkv7v93vwdak";
  };

  # New style AOSP has kernels outside of main source tree
  # https://source.android.com/setup/build/building-kernels
  # TODO: Any reason to use nixpkgs kernel stuff?
  customKernel = stdenv.mkDerivation {
    name = "kernel-${device}-${rev}";
    src = builtins.fetchGit {
      url = "https://android.googlesource.com/kernel/msm";
      rev = msmKernelRev;
      #ref = "tags/android-9.0.0_r0.74"; # branch: android-msm-marlin-3.18-pie-qpr3
  #    ref = import (runCommand "marlinKernelRev" {} ''
  #        shortrev=$(grep -a 'Linux version' ${sourceDir "device/google/marlin-kernel"}/.prebuilt_info/kernel/prebuilt_info_Image_lz4-dtb.asciipb | cut -d " " -f 6 | cut -d '-' -f 2 | sed 's/^g//g')
  #        echo \"$shortrev\" > $out
  #      '');
    };

    postPatch = lib.optionalString (verityx509 != null) ''
      openssl x509 -outform der -in ${verityx509} -out verity_user.der.x509
    '' + lib.optionalString enableWireguard ''
      # From android_kernel_wireguard/patch-kernel.sh
      sed -i "/^obj-\\\$(CONFIG_NETFILTER).*+=/a obj-\$(CONFIG_WIREGUARD) += wireguard/" net/Makefile
      sed -i "/^if INET\$/a source \"net/wireguard/Kconfig\"" net/Kconfig
      cp -r ${wireguardsrc}/src net/wireguard
      chmod u+w -R net/wireguard
      sed -i 's/tristate/bool/;s/default m/default y/;' net/wireguard/Kconfig
    '';

    nativeBuildInputs = [ perl bc nettools openssl rsync gmp libmpc mpfr lz4 ];

    enableParallelBuilding = true;
    makeFlags = [
      "ARCH=arm64"
      "CONFIG_COMPAT_VDSO=n"
      "CROSS_COMPILE=${prebuiltGCC}/bin/aarch64-linux-android-"
    ];

    preBuild = ''
      make ARCH=arm64 ${kernelConfigName}_defconfig
    '';

    installPhase = ''
      mkdir -p $out
      cp arch/arm64/boot/Image.lz4-dtb $out/Image.lz4-dtb
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

  # Get a bunch of utilities to generate keys
  keyTools = runCommandCC "android-key-tools-${rev}" { nativeBuildInputs = [ python pkgconfig ]; buildInputs = [ boringssl ]; } ''
    mkdir -p $out/bin

    cp ${sourceDir "development"}/tools/make_key $out/bin/make_key
    substituteInPlace $out/bin/make_key --replace openssl ${getBin openssl}/bin/openssl

    cc -o $out/bin/generate_verity_key \
      ${sourceDir "system/extras"}/verity/generate_verity_key.c \
      ${sourceDir "system/core"}/libcrypto_utils/android_pubkey.c \
      -I ${sourceDir "system/core"}/libcrypto_utils/include/ \
      -I ${boringssl}/include ${boringssl}/lib/libssl.a ${boringssl}/lib/libcrypto.a -lpthread

    cp ${sourceDir "external/avb"}/avbtool $out/bin/avbtool
    patchShebangs $out/bin
  '';

  # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
  generateKeysScript = writeScript "generate_keys.sh" ''
    #!${runtimeShell}

    export PATH=${getBin openssl}/bin:${keyTools}/bin:$PATH

    for key in {releasekey,platform,shared,media,verity,avb}; do
      # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
      ! make_key "$key" "$1" || exit 1
    done

    # Generate both verity and AVB keys. While not strictly necessary, there is
    # no harm in doing so--and the user may want to use the same keys for
    # multiple devices supporting different AVB modes.
    generate_verity_key -convert verity.x509.pem verity_key || exit 1
    avbtool extract_public_key --key avb.pk8 --output avb_pkmd.bin || exit 1
  '';

  # Make this into a script that can be run outside of nixpkgs
  signedTargetFiles = runCommand "${device}-signed_target_files-${buildID}.zip" { nativeBuildInputs = [ androidHostTools openssl pkgs.zip unzip jdk ]; } ''
    mkdir -p build/target/product/
    ln -s ${sourceDir "build/make"}/target/product/security build/target/product/security
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

  # TODO: Would be nice to have this script accept two arguments: keydir and target-files, so it could protentially be used against multiple target-files.
  # However, it currently depends on androidHostTools, which depends on androidBuild. So a change to target files would also require a rebuild of this anyway, which seems kindof dumb.
  # TODO: Do this in a temporary directory? It's ugly to make build dir and ./tmp/* dir gets cleared in these scripts too.
  releaseScript = writeScript "release.sh" ''
    #!${runtimeShell}

    export PATH=${androidHostTools}/bin:${openssl}/bin:${pkgs.zip}/bin:${unzip}/bin:${jdk}/bin:$PATH
    KEYSTOREPATH=$1

    # sign_target_files_apks.py and others below requires this directory to be here.
    mkdir -p build/target/product/
    ln -sf ${sourceDir "build/make"}/target/product/security build/target/product/security

    ${buildTools}/releasetools/sign_target_files_apks.py ${optionalString signBuild "-o -d $KEYSTOREPATH ${avbFlags}"} ${androidBuild.out}/aosp_${device}-target_files-${buildID}.zip ${device}-target_files-${buildID}.zip
    ${buildTools}/releasetools/ota_from_target_files.py ${optionalString signBuild "-k $KEYSTOREPATH/releasekey"} ${device}-target_files-${buildID}.zip ${device}-ota_update-${buildID}.zip
    ${buildTools}/releasetools/img_from_target_files.py ${device}-target_files-${buildID}.zip ${device}-img-${buildID}.zip

    DEVICE=${device};
    PRODUCT=${device};
    BUILD=${buildID};
    VERSION=${toLower buildID};

    get_radio_image() {
      grep -Po "require version-$1=\K.+" ${vendorFiles}/vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
    }
    BOOTLOADER=$(get_radio_image bootloader google_devices/$DEVICE)
    RADIO=$(get_radio_image baseband google_devices/$DEVICE)

    source ${sourceDir "device/common"}/generate-factory-images-common.sh

    rm -r build # Unsafe?
  '';
}

# Update with just img using: fastboot -w update <...>.img
