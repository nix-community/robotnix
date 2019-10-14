{ config, pkgs, lib, ... }:

with lib;
let
  usePatchedCoreutils = false;
  nixdroid-build = pkgs.callPackage ../buildenv.nix {};
  fakeuser = pkgs.callPackage ./fakeuser {};

  # TODO: Not exactly sure what i'm doing.
  putInStore = path: if (hasPrefix builtins.storeDir path) then path else (/. + path);
in
{
  options = {
    flavor = mkOption {
      default = "vanilla";
      type = types.str;
    };

    device = mkOption {
      type = types.str;
      description = "Code name of device build target";
      example = "marlin";
    };

    deviceFamily = mkOption {
      internal = true;
      type = types.str;
    };

    buildNumber = mkOption {
      default = "12345";
      type = types.str;
      description = "Set this to something meaningful, like the date. Needs to be unique for each build for the updater to work";
      example = "2019.08.12.1";
    };

    buildDateTime = mkOption {
      default = 1;
      type = types.int;
      description = "Seconds since the epoch that this build is taking place. Needs to be monotone increasing for the updater to work. e.g. output of \"date +%s\"";
      example = 1565645583;
    };

    buildType = mkOption {
      default = "user";
      type = types.strMatching "(user|userdebug|eng)";
      description = "one of \"user\", \"userdebug\", or \"eng\"";
    };

    androidVersion = mkOption {
      default = 10;
      type = types.int;
      description = "Used to select which android version to use";
    };

    apiLevel = mkOption {
      default = "28";
      type = types.str;
      internal = true;
    };

    localManifests = mkOption {
      default = [];
      type = types.listOf types.path;
    };

    system.additionalProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "PRODUCT_PACKAGES to add to build";
    };

    product.additionalProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "PRODUCT_PACKAGES to add to build";
    };

    removedProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "PRODUCT_PACKAGES to remove from build";
    };

    system.extraConfig = mkOption {
      default = "";
      type = types.lines;
      description = "Additional configuration to be included in system .mk file";
      internal = true;
    };

    product.extraConfig = mkOption {
      default = "";
      type = types.lines;
      description = "Additional configuration to be included in product .mk file";
      internal = true;
    };

    signBuild = mkOption {
      default = false;
      type = types.bool;
      description = "Whether to sign build using user-provided keys. Otherwise, build will be signed using insecure test-keys.";
    };

    keyStorePath = mkOption {
      type = types.str;
      description = "Absolute path to generated keys for signing";
    };

    avbMode = mkOption {
      type = types.strMatching "(verity_only|vbmeta_simple|vbmeta_chained)";
      default  = "vbmeta_chained"; # TODO: Not sure what a good default would be for non pixel devices.
    };

    # Random attrset to throw build products into
    build = mkOption {
      internal = true;
      default = {};
      type = types.attrs;
    };
  };

  config = {
    deviceFamily = mkOptionDefault config.device;

    apiLevel = mkIf (config.androidVersion == 10) "29";

    # Some derivations (like fdroid) need to know the fingerprints of the keys
    # even if we aren't signing. Set test-keys in that case. This is not an
    # unconditional default because we want the user to be forced to set
    # keyStorePath themselves if they select signBuild.
    keyStorePath = mkIf (!config.signBuild) (mkDefault (config.source.dirs."build/make".contents + /target/product/security));

    system.extraConfig = concatMapStringsSep "\n" (name: "PRODUCT_PACKAGES += ${name}") config.system.additionalProductPackages;
    product.extraConfig = concatMapStringsSep "\n" (name: "PRODUCT_PACKAGES += ${name}") config.product.additionalProductPackages;

    # TODO: The " \\" in the below sed is a bit flaky, and would require the line to end in " \\"
    # come up with something more robust.
    source.dirs."build/make".postPatch = ''
      ${concatMapStringsSep "\n" (name: "sed -i '/${name} \\\\/d' target/product/*.mk") config.removedProductPackages}
    '' + (if (config.androidVersion >= 10) then ''
      echo "\$(call inherit-product-if-exists, nixdroid/config/system.mk)" >> target/product/handheld_system.mk
      echo "\$(call inherit-product-if-exists, nixdroid/config/product.mk)" >> target/product/handheld_product.mk
    '' else ''
      echo "\$(call inherit-product-if-exists, nixdroid/config/system.mk)" >> target/product/core.mk
      echo "\$(call inherit-product-if-exists, nixdroid/config/product.mk)" >> target/product/core.mk
    '');

    source.dirs."nixdroid/config".contents = let
      systemMk = pkgs.writeTextFile { name = "system.mk"; text = config.system.extraConfig; };
      productMk = pkgs.writeTextFile { name = "product.mk"; text = config.product.extraConfig; };
    in
      pkgs.runCommand "nixdroid-config" {} ''
        mkdir -p $out
        cp ${systemMk} $out/system.mk
        cp ${productMk} $out/product.mk
      '';

    build = {
      # TODO: Is there a nix-native way to get this information instead of using IFD
      _keyPath = keyStorePath: name:
        let deviceCertificates = [ "releasekey" "platform" "media" "shared" "verity" ]; # Cert names used by AOSP
        in if builtins.elem name deviceCertificates
          then (if config.signBuild
            then "${keyStorePath}/${config.device}/${name}"
            else "${keyStorePath}/${name}")
          else "${keyStorePath}/${name}";
      keyPath = name: config.build._keyPath config.keyStorePath name;
      sandboxKeyPath = name: config.build._keyPath "/keys" name;

      x509 = name: putInStore "${config.build.keyPath name}.x509.pem";
      fingerprints = name:
        let
          avb_pkmd = putInStore "${config.keyStorePath}/${config.device}/avb_pkmd.bin";
      in if (name == "avb")
        then (import (pkgs.runCommand "avb-fingerprint" {} ''
          sha256sum ${avb_pkmd} | awk '{print $1}' | awk '{ print "\"" toupper($0) "\"" }' > $out
        ''))
        else (import (pkgs.runCommand "cert-fingerprint" {} ''
          ${pkgs.openssl}/bin/openssl x509 -noout -fingerprint -sha256 -in ${config.build.x509 name} | awk -F"=" '{print "\"" $2 "\"" }' | sed 's/://g' > $out
        ''));

      # Use NoCC here so we don't get extra environment variables that might conflict with AOSP build stuff. Like CC, NM, etc.
      android = pkgs.stdenvNoCC.mkDerivation rec {
        name = "nixdroid-${config.device}-${config.buildNumber}";
        srcs = [];

        # TODO: Clean this stuff up. unshare / nixdroid-build could probably be combined into a single utility.
        builder = pkgs.writeScript "builder.sh" ''
          #!${pkgs.runtimeShell}
          export useBindMounts=$(test -e /dev/fuse && echo true)
          export SAVED_UID=$UID
          export SAVED_GID=$GID

          # If useBindMounts is set then become a fake "root" in a new namespace so we can bind mount sources
          ${pkgs.toybox}/bin/cat << 'EOF' | ''${useBindMounts:+${pkgs.utillinux}/bin/unshare -m -r} ${pkgs.runtimeShell}
          source $stdenv/setup
          genericBuild
          EOF
        '';

        outputs = [ "out" "bin" ]; # This derivation builds AOSP release tools and target-files

        nativeBuildInputs = [ nixdroid-build fakeuser ];

        unpackPhase = ''
          ${optionalString usePatchedCoreutils "export PATH=${callPackage ../misc/coreutils.nix {}}/bin/:$PATH"}

          export rootDir=$PWD
          source ${pkgs.writeText "unpack.sh" config.source.unpackScript}
        '';

        configurePhase = ":";

        ANDROID_JAVA_HOME="${pkgs.jdk.home}"; # This is already set in android 10. They use their own prebuilt jdk
        BUILD_NUMBER=config.buildNumber;
        BUILD_DATETIME=config.buildDateTime;
        DISPLAY_BUILD_NUMBER="true"; # Enabling this shows the BUILD_ID concatenated with the BUILD_NUMBER in the settings menu

        buildPhase = ''
          export OUT_DIR_COMMON_BASE=$rootDir/out

          # Become the original user--not fake root.
          ${pkgs.toybox}/bin/cat << 'EOF2' | ''${useBindMounts:+fakeuser $SAVED_UID $SAVED_GID} ${pkgs.runtimeShell}

          # Enter an FHS user namespace
          ${pkgs.toybox}/bin/cat << 'EOF3' | nixdroid-build

          source build/envsetup.sh
          choosecombo release "aosp_${config.device}" ${config.buildType}
          export NINJA_ARGS="-j$NIX_BUILD_CORES -l$NIX_BUILD_CORES"
          make brillo_update_payload target-files-package
          echo $ANDROID_PRODUCT_OUT > ANDROID_PRODUCT_OUT

          EOF3
          EOF2
        '';

        # Kinda ugly to just throw all this in $bin/
        # Don't do patchelf in this derivation, just in case it fails we'd still like to have cached results
        # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
        installPhase = ''
          mkdir -p $out $bin
          export ANDROID_PRODUCT_OUT=$(cat ANDROID_PRODUCT_OUT)
          # Just grab top-level build products (for emulator, not recursive) + target_files
          find $ANDROID_PRODUCT_OUT -maxdepth 1 -type f | xargs -I {} cp --reflink=auto {} $out/
          cp --reflink=auto $ANDROID_PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/aosp_${config.device}-target_files-${config.buildNumber}.zip $out/

          cp --reflink=auto -r $OUT_DIR_COMMON_BASE/src/host/linux-x86/{bin,lib,lib64,usr,framework} $bin/
          cp --reflink=auto -r $OUT_DIR_COMMON_BASE/src/soong/host/linux-x86/* $bin/
        '';

        dontMoveLib64 = true;

        # Just included for convenience when building outside of nix.
        # TODO: Only build these scripts if entered using mkShell?
        debugUnpackScript = config.build.debugUnpackScript;
        debugPatchScript = config.build.debugPatchScript;
        debugEnterEnv = pkgs.writeText "debug-enter-env.sh" ''
          export useBindMounts=$(test -e /dev/fuse && echo true)
          export SAVED_UID=$UID
          export SAVED_GID=$GID
          ${pkgs.toybox}/bin/cat << 'EOF' | ''${useBindMounts:+${pkgs.utillinux}/bin/unshare -m -r} ${pkgs.runtimeShell}
          export rootDir=$PWD
          source ${pkgs.writeText "unpack.sh" config.source.unpackScript}

          # Become the original user--not fake root.
          ${pkgs.toybox}/bin/cat << 'EOF2' | ''${useBindMounts:+fakeuser $SAVED_UID $SAVED_GID} ${pkgs.runtimeShell}

          # Enter an FHS user namespace
          nixdroid-build -i < /dev/stdin

          EOF2
          EOF
        '';
      };

      hostTools = config.build.android.bin;

      checkAndroid = config.build.android.overrideAttrs (attrs: {
        outputs = [ "out" ];

        buildPhase = ''
          export OUT_DIR_COMMON_BASE=$rootDir/out

          # Become the original user--not fake root.
          ${pkgs.toybox}/bin/cat << 'EOF2' | ''${useBindMounts:+fakeuser $SAVED_UID $SAVED_GID} ${pkgs.runtimeShell}

          # Enter an FHS user namespace
          ${pkgs.toybox}/bin/cat << 'EOF3' | nixdroid-build

          source build/envsetup.sh
          choosecombo release "aosp_${config.device}" ${config.buildType}
          export NINJA_ARGS="-j$NIX_BUILD_CORES -l$NIX_BUILD_CORES -n"
          make brillo_update_payload target-files-package
          echo $ANDROID_PRODUCT_OUT > ANDROID_PRODUCT_OUT

          EOF3
          EOF2
        '';

        # Just copy some things that are useful for debugging
        installPhase = ''
          mkdir -p $out
          cp -r $OUT_DIR_COMMON_BASE/src/*.{log,gz} $out/
          cp -r $OUT_DIR_COMMON_BASE/src/.module_paths $out/
        '';
        # TODO: checkPhase that nixdroid mk file is in .module_paths/Android.mk.list

#        installPhase = ''
#          cp --reflink=auto -r $OUT_DIR_COMMON_BASE/src/ $out
#          # Don't include these FIFOs
#          rm -f $out/.ninja_fifo
#          rm -f $out/.path_interposer_log
#        '';
      });
    };
  };
}
