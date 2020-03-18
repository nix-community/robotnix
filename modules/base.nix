{ config, pkgs, lib, ... }:

with lib;
let
  usePatchedCoreutils = false;
  robotnix-build = pkgs.callPackage ../buildenv.nix {};
  fakeuser = pkgs.callPackage ./fakeuser {};

  # TODO: Not exactly sure what i'm doing.
  putInStore = path: if (hasPrefix builtins.storeDir path) then path else (/. + path);
in
{
  options = {
    flavor = mkOption {
      default = null;
      type = types.nullOr types.str;
    };

    device = mkOption {
      default = null;
      type = types.nullOr types.str;
      description = "Code name of device build target";
      example = "marlin";
    };

    deviceFamily = mkOption {
      default = null;
      type = types.nullOr types.str;
      internal = true;
    };

    arch = mkOption {
      default = "arm64";
      type = types.strMatching "(arm64|arm|x86_64|x86)";
      description = "Architecture of phone, usually set automatically by device";
    };

    variant = mkOption {
      default = "user";
      type = types.strMatching "(user|userdebug|eng)";
      description = "one of \"user\", \"userdebug\", or \"eng\"";
    };

    buildProduct = mkOption {
      type = types.str;
      description = "Product name for choosecombo/lunch (defaults to aosp_${config.device})";
    };

    buildType = mkOption {
      default = "release";
      type = types.strMatching "(release|debug)";
      description = "one of \"release\", \"debug\"";
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

    ccache.enable = mkEnableOption "ccache";

    # Random attrset to throw build products into
    build = mkOption {
      internal = true;
      default = {};
      type = types.attrs;
    };
  };

  config = {
    buildProduct = mkIf (config.device != null) (mkDefault "aosp_${config.device}");

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
      echo "\$(call inherit-product-if-exists, robotnix/config/system.mk)" >> target/product/handheld_system.mk
      echo "\$(call inherit-product-if-exists, robotnix/config/product.mk)" >> target/product/handheld_product.mk
    '' else ''
      echo "\$(call inherit-product-if-exists, robotnix/config/system.mk)" >> target/product/core.mk
      echo "\$(call inherit-product-if-exists, robotnix/config/product.mk)" >> target/product/core.mk
    '');

    source.dirs."robotnix/config".contents = let
      systemMk = pkgs.writeTextFile { name = "system.mk"; text = config.system.extraConfig; };
      productMk = pkgs.writeTextFile { name = "product.mk"; text = config.product.extraConfig; };
    in
      pkgs.runCommand "robotnix-config" {} ''
        mkdir -p $out
        cp ${systemMk} $out/system.mk
        cp ${productMk} $out/product.mk
      '';

    build = rec {
      # TODO: Is there a nix-native way to get this information instead of using IFD
      _keyPath = keyStorePath: name:
        let deviceCertificates = [ "releasekey" "platform" "media" "shared" "verity" ]; # Cert names used by AOSP
        in if builtins.elem name deviceCertificates
          then (if config.signBuild
            then "${keyStorePath}/${config.device}/${name}"
            else "${keyStorePath}/${replaceStrings ["releasekey"] ["testkey"] name}") # If not signBuild, use test keys from AOSP
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

      mkAndroid =
        { name, makeTargets, installPhase, outputs ? [ "out" ], ninjaArgs ? "" }:
        # Use NoCC here so we don't get extra environment variables that might conflict with AOSP build stuff. Like CC, NM, etc.
        pkgs.stdenvNoCC.mkDerivation (rec {
          inherit name;
          srcs = [];

          # TODO: Clean this stuff up. unshare / robotnix-build could probably be combined into a single utility.
          builder = pkgs.writeScript "builder.sh" ''
            #!${pkgs.runtimeShell}
            export SAVED_UID=$(${pkgs.coreutils}/bin/id -u)
            export SAVED_GID=$(${pkgs.coreutils}/bin/id -g)

            # Become a fake "root" in a new namespace so we can bind mount sources
            ${pkgs.toybox}/bin/cat << 'EOF' | ${pkgs.utillinux}/bin/unshare -m -r ${pkgs.runtimeShell}
            source $stdenv/setup
            genericBuild
            EOF
          '';

          inherit outputs;

          nativeBuildInputs = [ robotnix-build fakeuser ];

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
            export OUT_DIR=$rootDir/out

            # Become the original user--not fake root.
            ${pkgs.toybox}/bin/cat << 'EOF2' | fakeuser $SAVED_UID $SAVED_GID} robotnix-build

            source build/envsetup.sh
            choosecombo ${config.buildType} ${config.buildProduct} ${config.variant}
            export NINJA_ARGS="${toString ninjaArgs}"
            #export NINJA_ARGS="-j$NIX_BUILD_CORES -l$NIX_BUILD_CORES ${toString ninjaArgs}"
            make ${toString makeTargets}
            echo $ANDROID_PRODUCT_OUT > ANDROID_PRODUCT_OUT

            EOF2
          '';

          inherit installPhase;

          dontFixup = true;
          dontMoveLib64 = true;
        } // (lib.optionalAttrs config.ccache.enable {
          CCACHE_EXEC = pkgs.ccache + /bin/ccache;
          USE_CCACHE = "true";
          CCACHE_DIR = "/var/cache/ccache"; # Make configurable?
          CCACHE_UMASK = "007"; # CCACHE_DIR should be user root, group nixbld
        }));

      android = mkAndroid {
        name = "robotnix-${config.buildProduct}-${config.buildNumber}";
        makeTargets = [ "target-files-package" "otatools-package" ]; # TODO Separate into two derivations?
        # Don't do patchelf in this derivation, just in case it fails we'd still like to have cached results
        # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
        installPhase = ''
          mkdir -p $out
          export ANDROID_PRODUCT_OUT=$(cat ANDROID_PRODUCT_OUT)

          cp --reflink=auto $ANDROID_PRODUCT_OUT/otatools.zip $out/
          cp --reflink=auto $ANDROID_PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/${config.buildProduct}-target_files-${config.buildNumber}.zip $out/
        '';
      };

      checkAndroid = mkAndroid {
        name = "robotnix-check-${config.device}-${config.buildNumber}";
        makeTargets = [ "target-files-package" "otatools-package" ];
        ninjaArgs = "-n"; # Pretend to run the actual build steps
        # Just copy some things that are useful for debugging
        installPhase = ''
          mkdir -p $out
          cp -r $OUT_DIR/*.{log,gz} $out/
          cp -r $OUT_DIR/.module_paths $out/
        '';
      };

      otaTools = pkgs.stdenv.mkDerivation {
        name = "ota-tools";
        src = "${config.build.android}/otatools.zip";
        sourceRoot = ".";
        nativeBuildInputs = with pkgs; [ unzip autoPatchelfHook protobuf pythonPackages.pytest ];
        buildInputs = [ (pkgs.python.withPackages (p: [ p.protobuf ])) ];
        postPatch = ''
          # Replace some python binaries with the original python files.
          # The soong-compiled versions all have "Failed to import the site module" error
          cp ${config.source.dirs."external/avb".contents}/avbtool bin/avbtool
          cp ${config.source.dirs."system/core".contents}/mkbootimg/mkbootimg.py bin/mkbootimg
          cp ${config.source.dirs."system/extras".contents}/ext4_utils/mkuserimg_mke2fs.py bin/mkuserimg_mke2fs
          cp ${config.source.dirs."bootable/recovery".contents}/update_verifier/care_map_generator.py bin/care_map_generator
          protoc --python_out=bin/ -I ${config.source.dirs."bootable/recovery".contents}/update_verifier \
            ${config.source.dirs."bootable/recovery".contents}/update_verifier/care_map.proto

          for name in boot_signer verity_signer; do
            substituteInPlace bin/$name --replace java ${lib.getBin pkgs.jre8_headless}/bin/java
          done

          substituteInPlace releasetools/common.py \
            --replace 'self.search_path = platform_search_path.get(sys.platform)' "self.search_path = \"$out\"" \
            --replace 'self.java_path = "java"' 'self.java_path = "${lib.getBin pkgs.jre8_headless}/bin/java"' \
            --replace '"zip"' '"${lib.getBin pkgs.zip}/bin/zip"' \
            --replace '"unzip"' '"${lib.getBin pkgs.unzip}/bin/unzip"'

          substituteInPlace bin/lib/shflags/shflags \
            --replace "FLAGS_GETOPT_CMD:-getopt" "FLAGS_GETOPT_CMD:-${pkgs.getopt}/bin/getopt"

          substituteInPlace bin/brillo_update_payload \
            --replace "which delta_generator" "${pkgs.which}/bin/which delta_generator" \
            --replace "xxd " "${lib.getBin pkgs.toybox}/bin/xxd " \
            --replace "cgpt " "${lib.getBin pkgs.vboot_reference}/bin/cgpt " \
            --replace "look " "${lib.getBin pkgs.utillinux}/bin/look " \
            --replace "unzip " "${lib.getBin pkgs.unzip}/bin/unzip "

          for name in bin/avbtool releasetools/{check_ota_package_signature,sign_target_files_apks,test_common,common,test_ota_from_target_files,ota_from_target_files,check_target_files_signatures}.py; do
            substituteInPlace "$name" \
              --replace "'openssl'" "'${lib.getBin pkgs.openssl}/bin/openssl'" \
              --replace "\"openssl\"" "\"${lib.getBin pkgs.openssl}/bin/openssl\""
          done
          for name in releasetools/testdata/{payload_signer,signing_helper}.sh; do
            substituteInPlace "$name" \
              --replace "openssl" "${lib.getBin pkgs.openssl}/bin/openssl"
          done

          for name in releasetools/test_*.py; do
            substituteInPlace "$name" \
              --replace "@test_utils.SkipIfExternalToolsUnavailable()" ""
          done

          # This test is broken
          substituteInPlace releasetools/test_sign_target_files_apks.py \
            --replace test_ReadApexKeysInfo_presignedKeys skip_test_ReadApexKeysInfo_presignedKeys

          # These tests are too slow
          substituteInPlace releasetools/test_common.py \
            --replace test_ZipWrite skip_test_zipWrite
        '';
        installPhase = ''
          mkdir -p $out
          cp --reflink=auto -r * $out/
        '';
        # Since we copy everything from build dir into $out, we don't want
        # env-vars file which contains a bunch of references we don't need
        noDumpEnvVars = true;

        doInstallCheck = true;
        installCheckPhase = ''
          cd $out/releasetools
          export PATH=$out/bin:$PATH
          export EXT2FS_NO_MTAB_OK=yes
          pytest
        '';
      };

        # Just included for convenience when building outside of nix.
        # TODO: Better way than creating all these scripts and feeding with init-file?
#        debugUnpackScript = config.build.debugUnpackScript;
#        debugPatchScript = config.build.debugPatchScript;
        debugEnterEnv = pkgs.writeScript "debug-enter-env.sh" ''
          #!${pkgs.runtimeShell}
          export SAVED_UID=$(${pkgs.coreutils}/bin/id -u)
          export SAVED_GID=$(${pkgs.coreutils}/bin/id -g)
          ${pkgs.utillinux}/bin/unshare -m -r ${pkgs.writeScript "debug-enter-env2.sh" ''
          export rootDir=$PWD
          source ${pkgs.writeText "unpack.sh" config.source.unpackScript}

          # Become the original user--not fake root. Enter an FHS user namespace
          ${fakeuser}/bin/fakeuser $SAVED_UID $SAVED_GID ${robotnix-build}/bin/robotnix-build
          ''}
        '';
    };
  };
}
