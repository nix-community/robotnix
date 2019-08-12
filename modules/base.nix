{ config, pkgs, lib, ... }:

with lib;
let
  usePatchedCoreutils = false;
  nixdroid-env = pkgs.callPackage ../buildenv.nix {};
  flex = pkgs.callPackage ../misc/flex-2.5.39.nix {};

  # Using IFD here, because its too damn convenient
  certFingerprint = x509: import (pkgs.runCommand "cert-fingerprint" {} ''
    ${pkgs.openssl}/bin/openssl x509 -noout -fingerprint -sha256 -in ${x509} | awk -F"=" '{print "\"" $2 "\"" }' | sed 's/://g' > $out
  '');

  certOptions = certName: {
    x509 = mkOption {
      type = types.path;
      description = "x509 certificate for ${certName} key";
    };

    fingerprint = mkOption {
      type = types.str;
      description = "SHA256 fingerprint for ${certName} key";
      internal = true;
      default = certFingerprint config.certs.${certName}.x509;
    };
  };
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

    certs = {
      platform = certOptions "platform";
      verity = certOptions "verity";
    };

    avb = {
      pkmd = mkOption {
        type = types.path;
        description = "avb_pkmd.bin file";
      };

      fingerprint = mkOption {
        type = types.str;
        internal = true;
        # TODO: Is there a nix-native way to get this information?
        default = import (pkgs.runCommand "avb-fingerprint" {} ''
          sha256sum ${config.avb.pkmd} | awk '{print $1}' | awk '{ print "\"" toupper($0) "\"" }' > $out
        '');
      };
    };

    build = mkOption {
      internal = true;
      default = {};
      type = types.attrs;
    };
  };

  config = {
    deviceFamily = mkDefault {
      marlin = "marlin"; # Pixel XL
      sailfish = "marlin"; # Pixel
      taimen = "taimen"; # Pixel 2 XL
      walleye = "taimen"; # Pixel 2
      crosshatch = "crosshatch"; # Pixel 3 XL
      blueline = "crosshatch"; # Pixel 3
      bonito = "bonito"; # Pixel 3a XL
      sargo = "bonito"; # Pixel 3a
    }.${config.device};

    build = {
      # Use NoCC here so we don't get extra environment variables that might conflict with AOSP build stuff. Like CC, NM, etc.
      android = pkgs.stdenvNoCC.mkDerivation rec {
        name = "nixdroid-${config.device}-${config.buildNumber}";
        srcs = [];

        outputs = [ "out" "bin" ]; # This derivation builds AOSP release tools and target-files

        unpackPhase = ''
          ${optionalString usePatchedCoreutils "export PATH=${callPackage ../misc/coreutils.nix {}}/bin/:$PATH"}

          source ${pkgs.writeText "unpack.sh" config.source.unpackScript}
        '';

        patches = config.source.patches;
        patchFlags = [ "-p1" "--no-backup-if-mismatch" ]; # Patches that don't apply exactly will create .orig files, which the android build system doesn't like seeing.

        # Fix a locale issue with included flex program
        postPatch = ''
          ln -sf ${flex}/bin/flex prebuilts/misc/linux-x86/flex/flex-2.5.39

          ${concatMapStringsSep "\n" (name: "echo PRODUCT_PACKAGES += ${name} >> build/make/target/product/core.mk") config.additionalProductPackages}
          ${concatMapStringsSep "\n" (name: "sed -i '/${name} \\\\/d' build/make/target/product/*.mk") config.removedProductPackages}

          ${config.source.postPatch}
        '';
        # TODO: The " \\" in the above sed is a bit flaky, and would require the line to end in " \\"
        # come up with something more robust.

        ANDROID_JAVA_HOME="${pkgs.jdk.home}";
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
