{ config, pkgs, lib, ... }:

with lib;
let
  usePatchedCoreutils = false;
  nixdroid-env = pkgs.callPackage ../buildenv.nix {};

  # TODO: Not exactly sure what i'm doing.
  putInStore = path: if (hasPrefix builtins.storeDir path) then path else (/. + path);
in
{
  options = {
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
      type = types.str;
      description = "Set this to something meaningful, like the date. Needs to be unique for each build for the updater to work";
      example = "2019.08.12.1";
    };

    buildDateTime = mkOption {
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
      default = "9";
      type = types.str;
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

    additionalProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "PRODUCT_PACKAGES to add to build";
    };

    removedProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "PRODUCT_PACKAGES to remove from build";
    };

    extraConfig = mkOption {
      default = "";
      type = types.lines;
      description = "Additional configuration to be included in product .mk file";
      internal = true;
    };

    signBuild = mkOption {
      default = true;
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
    apiLevel = mkIf (config.androidVersion == "10") mkDefault "29";

    # Some derivations (like fdroid) need to know the fingerprints of the keys
    # even if we aren't signing. Set test-keys in that case. This is not an
    # unconditional default because we want the user to be foreced to set
    # keyStorePath themselves if they select signBuild.
    keyStorePath = mkIf (!config.signBuild) (config.source.dirs."build/make".contents + /target/product/security);

    extraConfig = concatMapStringsSep "\n" (name: "PRODUCT_PACKAGES += ${name}") config.additionalProductPackages;

    # TODO: The " \\" in the below sed is a bit flaky, and would require the line to end in " \\"
    # come up with something more robust.
    source.postPatch = ''
      ${concatMapStringsSep "\n" (name: "sed -i '/${name} \\\\/d' build/make/target/product/*.mk") config.removedProductPackages}

      # this is newer location in master
      mk_file=./build/make/target/product/handheld_system.mk
      if [ ! -f ''${mk_file} ]; then
        # this is older location
        mk_file=./build/make/target/product/core.mk
        if [ ! -f ''${mk_file} ]; then
          echo "Expected handheld_system.mk or core.mk do not exist"
          exit 1
        fi
      fi

      mkdir -p nixdroid/
      cp -f ${pkgs.writeText "config.mk" config.extraConfig} nixdroid/config.mk
      chmod u+w nixdroid/config.mk
      echo "\$(call inherit-product-if-exists, nixdroid/config.mk)" >> ''${mk_file}
    '';

    build = {
      # TODO: Is there a nix-native way to get this information instead of using IFD
      _keyPath = keyStorePath: name:
        let deviceCertificates = [ "release" "platform" "media" "shared" "verity" ]; # Cert names used by AOSP
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

        outputs = [ "out" "bin" ]; # This derivation builds AOSP release tools and target-files

        unpackPhase = ''
          ${optionalString usePatchedCoreutils "export PATH=${callPackage ../misc/coreutils.nix {}}/bin/:$PATH"}

          source ${pkgs.writeText "unpack.sh" config.source.unpackScript}
        '';

        # Just included for convenience when building outside of nix.
        debugUnpackScript = config.build.debugUnpackScript;
        # To easily build outside nix:
        # nix-shell ... -A config.build.android
        # source $debugUnpackScript       # should just create files under nixdroid/
        # Apply any patches in $patches
        # runHook postPatch

        patches = config.source.patches;
        patchFlags = [ "-p1" "--no-backup-if-mismatch" ]; # Patches that don't apply exactly will create .orig files, which the android build system doesn't like seeing.

        postPatch = config.source.postPatch;

        ANDROID_JAVA_HOME="${pkgs.jdk.home}"; # This is already set in android 10. They use their own prebuilt jdk
        BUILD_NUMBER=config.buildNumber;
        BUILD_DATETIME=config.buildDateTime;
        DISPLAY_BUILD_NUMBER="true"; # Enabling this shows the BUILD_ID concatenated with the BUILD_NUMBER in the settings menu
        ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G";

        # Alternative is to just "make target-files-package brillo_update_payload
        # Parts from https://github.com/GrapheneOS/script/blob/pie/release.sh
        buildPhase = ''
          cat << 'EOF' | ${nixdroid-env}/bin/nixdroid-build
          source build/envsetup.sh
          choosecombo release "aosp_${config.device}" ${config.buildType}
          make otatools-package target-files-package
          EOF
        '';

        # Kinda ugly to just throw all this in $bin/
        # Don't do patchelf in this derivation, just in case it fails we'd still like to have cached results
        installPhase = ''
          mkdir -p $out $bin
          cp --reflink=auto -r out/target/product/${config.device}/obj/PACKAGING/target_files_intermediates/aosp_${config.device}-target_files-${config.buildNumber}.zip $out/
          cp --reflink=auto -r out/host/linux-x86/{bin,lib,lib64,usr,framework} $bin/
        '';

        configurePhase = ":";
        dontMoveLib64 = true;
      };

      # Tools that were built for the host in the process of building the target files.
      # Do the patchShebangs / patchelf stuff in this derivation so it failing for any reason doesn't stop the main android build
      hostTools = pkgs.stdenv.mkDerivation {
        name = "android-host-tools";
        src = config.build.android.bin;
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = with pkgs; [ python ncurses5 ]; # One of the utilities needs libncurses.so.5 but it's not in the lib/ dir of the android build files.
        installPhase = ''
          mkdir -p $out
          cp --reflink=auto -r * $out
        '';
        dontMoveLib64 = true;
      };
    };
  };
}
