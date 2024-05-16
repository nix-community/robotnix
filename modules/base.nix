# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib)
    mkIf mkMerge mkOption mkOptionDefault mkEnableOption mkDefault types;

  fakeuser = pkgs.callPackage ./fakeuser {};

  # Taken from https://github.com/edolstra/flake-compat/
  # Format number of seconds in the Unix epoch as %Y%m%d%H
  formatSecondsSinceEpoch = t:
    let
      rem = x: y: x - x / y * y;
      days = t / 86400;
      secondsInDay = rem t 86400;
      hours = secondsInDay / 3600;
      minutes = (rem secondsInDay 3600) / 60;
      seconds = rem t 60;

      # Courtesy of https://stackoverflow.com/a/32158604.
      z = days + 719468;
      era = (if z >= 0 then z else z - 146096) / 146097;
      doe = z - era * 146097;
      yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
      y = yoe + era * 400;
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
      mp = (5 * doy + 2) / 153;
      d = doy - (153 * mp + 2) / 5 + 1;
      m = mp + (if mp < 10 then 3 else -9);
      y' = y + (if m <= 2 then 1 else 0);

      pad = s: if builtins.stringLength s < 2 then "0" + s else s;
    in "${toString y'}${pad (toString m)}${pad (toString d)}${pad (toString hours)}";
in
{
  options = {
    flavor = mkOption {
      default = null;
      type = types.nullOr types.str;
      description = ''
        Set to one of robotnix's supported flavors.
        Current options are `vanilla`, `grapheneos`, and `lineageos`.
      '';
      example = "vanilla";
    };

    device = mkOption {
      default = null;
      type = types.nullOr types.str;
      description = "Code name of device build target";
      example = "marlin";
    };

    deviceDisplayName = mkOption {
      default = null;
      type = types.nullOr types.str;
      description = "Display name of device build target";
      example = "Pixel XL";
    };

    deviceFamily = mkOption {
      default = null;
      type = types.nullOr types.str;
      internal = true;
    };

    arch = mkOption {
      default = "arm64";
      type = types.enum [ "arm64" "arm" "x86_64" "x86" ];
      description = "Architecture of phone, usually set automatically by device";
    };

    variant = mkOption {
      default = "user";
      type = types.enum [ "user" "userdebug" "eng" ];
      description = ''
        `user` has limited access and is suited for production.
        `userdebug` is like user but with root access and debug capability.
        `eng` is the development configuration with additional debugging tools.
      '';
    };

    productName = mkOption {
      type = types.str;
      description = "Product name for choosecombo/lunch";
      defaultText = "\${productNamePrefix}\${device}";
      example = "aosp_crosshatch";
    };

    productNamePrefix = mkOption {
      default = "aosp_";
      type = types.str;
      description = "Prefix for product name used with choosecombo/lunch";
    };

    buildType = mkOption {
      default = "release";
      type = types.enum [ "release" "debug" ];
      description = "one of \"release\", \"debug\"";
    };

    buildNumber = mkOption {
      type = types.str;
      description = ''
        Set this to something meaningful to identify the build.
        Defaults to `YYYYMMDDHH` based on `buildDateTime`.
        Should be unique for each build for disambiguation.
      '';
      example = "201908121";
    };

    buildDateTime = mkOption {
      type = types.int;
      description = ''
        Unix time (seconds since the epoch) that this build is taking place.
        Needs to be monotonically increasing for each build if you use the over-the-air (OTA) update mechanism.
        e.g. output of `date +%s`
        '';
      example = 1565645583;
      default = with lib; foldl' max 1 (mapAttrsToList (n: v: if v.enable then v.dateTime else 1) config.source.dirs);
      defaultText = "*maximum of source.dirs.<name>.dateTime*";
    };

    androidVersion = mkOption {
      default = 12;
      type = types.int;
      description = "Used to select which Android version to use";
    };

    flavorVersion = mkOption {
      type = types.str;
      internal = true;
      description = "Version used by this flavor of Android";
    };

    apiLevel = mkOption {
      type = types.int;
      internal = true;
      readOnly = true;
    };

    # TODO: extract system/product/vendor options into a submodule
    system.additionalProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "`PRODUCT_PACKAGES` to add under `system` partition.";
    };

    product.additionalProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "`PRODUCT_PACKAGES` to add under `product` partition.";
    };

    vendor.additionalProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "`PRODUCT_PACKAGES` to add under `vendor` partition.";
    };

    removedProductPackages = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "`PRODUCT_PACKAGES` to remove from build";
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

    vendor.extraConfig = mkOption {
      default = "";
      type = types.lines;
      description = "Additional configuration to be included in vendor .mk file";
      internal = true;
    };

    ccache.enable = mkEnableOption "ccache";

    envPackages = mkOption {
      type = types.listOf types.package;
      internal = true;
      default = [];
    };

    envVars = mkOption {
      type = types.attrsOf types.str;
      internal = true;
      default = {};
    };

    useReproducibilityFixes = mkOption {
      type = types.bool;
      default = true;
      description = "Apply additional fixes for reproducibility";
    };

    # Random attrset to throw build products into
    build = mkOption {
      internal = true;
      default = {};
      type = types.attrs;
    };
  };

  config = mkMerge [
  (mkIf (lib.elem config.device ["arm64" "arm" "x86" "x86_64"]) {
    # If this is a generic build for an arch, just set the arch as well
    arch = mkDefault config.device;
    deviceFamily = mkDefault "generic";
  })
  {
    apiLevel = {
      # TODO: If we start building older androids and need the distinction
      # between 7 and 7.1, we should probably switch to a string androidVersion
      "7" = 25; # Assuming 7.1
      "8" = 27; # Assuming 8.1
      "9" = 28;
      "10" = 29;
      "11" = 30;
      "12" = 32;
      "13" = 33;
    }.${builtins.toString config.androidVersion} or 32;

    buildNumber = mkOptionDefault (formatSecondsSinceEpoch config.buildDateTime);

    productName = mkIf (config.device != null) (mkOptionDefault "${config.productNamePrefix}${config.device}");

    system.extraConfig = lib.concatMapStringsSep "\n" (name: "PRODUCT_PACKAGES += ${name}") config.system.additionalProductPackages;
    product.extraConfig = lib.concatMapStringsSep "\n" (name: "PRODUCT_PACKAGES += ${name}") config.product.additionalProductPackages;
    vendor.extraConfig = lib.concatMapStringsSep "\n" (name: "PRODUCT_PACKAGES += ${name}") config.vendor.additionalProductPackages;

    # TODO: The " \\" in the below sed is a bit flaky, and would require the line to end in " \\"
    # come up with something more robust.
    source.dirs."build/make".postPatch = ''
      ${lib.concatMapStringsSep "\n" (name: "sed -i '/${name} \\\\/d' target/product/*.mk") config.removedProductPackages}
    '' + (if (config.androidVersion >= 10) then ''
      echo "\$(call inherit-product-if-exists, robotnix/config/system.mk)" >> target/product/handheld_system.mk
      echo "\$(call inherit-product-if-exists, robotnix/config/product.mk)" >> target/product/handheld_product.mk
      echo "\$(call inherit-product-if-exists, robotnix/config/vendor.mk)" >> target/product/handheld_vendor.mk
    '' else if (config.androidVersion >= 8) /* FIXME Unclear if android 8 has these... */ then ''
      echo "\$(call inherit-product-if-exists, robotnix/config/system.mk)" >> target/product/core.mk
      echo "\$(call inherit-product-if-exists, robotnix/config/product.mk)" >> target/product/core.mk
      echo "\$(call inherit-product-if-exists, robotnix/config/vendor.mk)" >> target/product/core.mk
    '' else ''
      # no-op as it's not present in android 7 and under?
    '');

    source.dirs."robotnix/config".src = let
      systemMk = pkgs.writeTextFile { name = "system.mk"; text = config.system.extraConfig; };
      productMk = pkgs.writeTextFile { name = "product.mk"; text = config.product.extraConfig; };
      vendorMk = pkgs.writeTextFile { name = "vendor.mk"; text = config.vendor.extraConfig; };
    in
      pkgs.runCommand "robotnix-config" {} ''
        mkdir -p $out
        cp ${systemMk} $out/system.mk
        cp ${productMk} $out/product.mk
        cp ${vendorMk} $out/vendor.mk
      '';

    envVars = mkMerge [
      {
        BUILD_NUMBER = config.buildNumber;
        BUILD_DATETIME = builtins.toString config.buildDateTime;
        DISPLAY_BUILD_NUMBER="true"; # Enabling this shows the BUILD_ID concatenated with the BUILD_NUMBER in the settings menu
      }
      (mkIf config.ccache.enable {
        CCACHE_EXEC = pkgs.ccache + /bin/ccache;
        USE_CCACHE = "true";
        CCACHE_DIR = "/var/cache/ccache"; # Make configurable?
        CCACHE_UMASK = "007"; # CCACHE_DIR should be user root, group nixbld
        CCACHE_COMPILERCHECK = "content"; # Default is a mtime+size check. We can't fully rely on that.
      })
      (mkIf (config.androidVersion >= 11) {
        # Android 11 ninja filters env vars for more correct incrementalism.
        # However, env vars like LD_LIBRARY_PATH must be set for nixpkgs build-userenv-fhs to work
        ALLOW_NINJA_ENV = "true";
      })
    ];

    build = rec {
      mkAndroid =
        { name, makeTargets, installPhase, outputs ? [ "out" ], ninjaArgs ? "" }:
        # Use NoCC here so we don't get extra environment variables that might conflict with AOSP build stuff. Like CC, NM, etc.
        pkgs.stdenvNoCC.mkDerivation ({
          inherit name;
          srcs = [];

          # TODO: update in the future, might not be required.
          # gets permissed denied if not set, in some of our deps
          dontUpdateAutotoolsGnuConfigScripts = true;

          # TODO: Clean this stuff up. unshare / robotnix-build could probably be combined into a single utility.
          builder = pkgs.writeShellScript "builder.sh" ''
            export SAVED_UID=$(${pkgs.coreutils}/bin/id -u)
            export SAVED_GID=$(${pkgs.coreutils}/bin/id -g)

            # Become a fake "root" in a new namespace so we can bind mount sources
            ${pkgs.toybox}/bin/cat << 'EOF' | ${pkgs.util-linux}/bin/unshare -m -r ${pkgs.runtimeShell}
            set -euo pipefail
            source $stdenv/setup
            genericBuild
            EOF
          '';

          inherit outputs;

          requiredSystemFeatures = [ "big-parallel" ];

          nativeBuildInputs = [ config.build.env fakeuser ];

          unpackPhase = ''
            export rootDir=$PWD
            source ${config.build.unpackScript}
          '';

          dontConfigure = true;

          # This was originally in the buildPhase, but building the sdk / atree would complain for unknown reasons when it was set
          # export OUT_DIR=$rootDir/out
          buildPhase = ''
            # Become the original user--not fake root.
            ${pkgs.toybox}/bin/cat << 'EOF2' | fakeuser $SAVED_UID $SAVED_GID robotnix-build
            set -e -o pipefail

            ${lib.optionalString (config.androidVersion >= 6 && config.androidVersion <= 8) ''
            # Needed for the jack compilation server
            # https://source.android.com/setup/build/jack
            mkdir -p $HOME
            export USER=foo
            ''}
            source build/envsetup.sh
            choosecombo ${config.buildType} ${config.productName} ${config.variant}

            # Fail early if the product was not selected properly
            test -n "$TARGET_PRODUCT" || exit 1

            export NINJA_ARGS="-j$NIX_BUILD_CORES ${toString ninjaArgs}"
            m ${toString makeTargets} | cat
            echo $ANDROID_PRODUCT_OUT > ANDROID_PRODUCT_OUT

            EOF2
          '';

          installPhase = ''
            export ANDROID_PRODUCT_OUT=$(cat ANDROID_PRODUCT_OUT)
          '' + installPhase;

          dontFixup = true;
          dontMoveLib64 = true;
        } // config.envVars);

      android = mkAndroid {
        name = "robotnix-${config.productName}-${config.buildNumber}";
        makeTargets = [ "target-files-package" "otatools-package" ];
        # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
        installPhase = ''
          mkdir -p $out
          cp --reflink=auto $ANDROID_PRODUCT_OUT/otatools.zip $out/
          cp --reflink=auto $ANDROID_PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/${config.productName}-target_files-${config.buildNumber}.zip $out/
        '';
      };

      checkAndroid = mkAndroid {
        name = "robotnix-check-${config.device}-${config.buildNumber}";
        makeTargets = [ "target-files-package" "otatools-package" ];
        ninjaArgs = "-n"; # Pretend to run the actual build steps
        # Just copy some things that are useful for debugging
        installPhase = ''
          mkdir -p $out
          cp -r out/*.{log,gz} $out/
          cp -r out/.module_paths $out/
        '';
      };

      moduleInfo = mkAndroid {
        name = "robotnix-module-info-${config.device}-${config.buildNumber}.json";
        # Can't use absolute path from $ANDROID_PRODUCT_OUT here since make needs a relative path
        makeTargets = [ "$(get_build_var PRODUCT_OUT)/module-info.json" ];
        installPhase = ''
          cp $ANDROID_PRODUCT_OUT/module-info.json $out
        '';
      };

      # Save significant build time by building components simultaneously.
      mkAndroidComponents = targets: mkAndroid {
        name = "robotnix-android-components";
        makeTargets = targets ++ [ "$(get_build_var PRODUCT_OUT)/module-info.json" ];
        installPhase = ''
          ${pkgs.python3.interpreter} - "$out" "$ANDROID_PRODUCT_OUT/module-info.json" ${lib.escapeShellArgs targets} << EOF
          import json
          import os
          import shutil
          import sys
          outdir = sys.argv[1]
          module_info = json.load(open(sys.argv[2]))
          targets = sys.argv[3:]
          for target in targets:
              if target in module_info:
                  for item in module_info[target]['installed']:
                      if item.startswith('out/'):
                          output = outdir + item[3:]
                      else:
                          output = outdir + '/' + item
                      os.makedirs(os.path.dirname(output), exist_ok=True)
                      shutil.copyfile(item, output)
          EOF
        '';
      };

      mkAndroidComponent = target: (mkAndroidComponents [ target ]).overrideAttrs (_: { name=target; });

      otaTools = fixOtaTools "${config.build.android}/otatools.zip";

      # Also make a version without building all of target-files-package.  This
      # is just for debugging. We save significant time for a full build by
      # normally building target-files-package and otatools-package
      # simultaneously
      otaToolsQuick = fixOtaTools (mkAndroid {
        name = "otatools.zip";
        makeTargets = [ "otatools-package" ];
        installPhase = ''
          cp --reflink=auto $ANDROID_PRODUCT_OUT/otatools.zip $out
        '';
      });

      fixOtaTools = src: pkgs.stdenv.mkDerivation {
        name = "ota-tools";
        inherit src;
        sourceRoot = ".";
        nativeBuildInputs = with pkgs; [ unzip python3Packages.pytest ];
        buildInputs = [ (pkgs.python3.withPackages (p: [ p.protobuf ])) ];
        postPatch = lib.optionalString (config.androidVersion == 11) ''
          cp bin/debugfs_static bin/debugfs
        '' + lib.optionalString (config.androidVersion <= 10) ''
          substituteInPlace releasetools/common.py \
            --replace 'self.search_path = platform_search_path.get(sys.platform)' "self.search_path = \"$out\"" \
        '';

        dontBuild = true;

        installPhase = ''
          for file in bin/*; do
            isELF "$file" || continue
            bash ${../scripts/patchelf-prefix.sh} "$file" "${pkgs.stdenv.cc.bintools.dynamicLinker}" || continue
          done
        '' + ''
          mkdir -p $out
          cp --reflink=auto -r * $out/
        '' + lib.optionalString (config.androidVersion <= 10) ''
          ln -s $out/releasetools/sign_target_files_apks.py $out/bin/sign_target_files_apks
          ln -s $out/releasetools/img_from_target_files.py $out/bin/img_from_target_files
          ln -s $out/releasetools/ota_from_target_files.py $out/bin/ota_from_target_files
        '';

        # Since we copy everything from build dir into $out, we don't want
        # env-vars file which contains a bunch of references we don't need
        noDumpEnvVars = true;

        # This breaks the executables with embedded python interpreters
        dontStrip = true;
      };

      # Just included for convenience when building outside of nix.
      # TODO: Better way than creating all these scripts and feeding with init-file?
#        debugUnpackScript = config.build.debugUnpackScript;
#        debugPatchScript = config.build.debugPatchScript;
      debugEnterEnv = pkgs.writeShellScript "debug-enter-env.sh" ''
        export SAVED_UID=$(${pkgs.coreutils}/bin/id -u)
        export SAVED_GID=$(${pkgs.coreutils}/bin/id -g)
        ${pkgs.util-linux}/bin/unshare -m -r ${pkgs.writeShellScript "debug-enter-env2.sh" ''
        export rootDir=$PWD
        source ${config.build.unpackScript}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=${value}") config.envVars)}

        # Become the original user--not fake root. Enter an FHS user namespace
        ${fakeuser}/bin/fakeuser $SAVED_UID $SAVED_GID ${config.build.env}/bin/robotnix-build
        ''}
      '';

      env = let
        # Ugly workaround needed in Android >= 12
        patchedPkgs = pkgs.extend
          (self: super: {
            bashInteractive = super.bashInteractive.overrideAttrs (attrs: {
              # Removed:
              # -DDEFAULT_PATH_VALUE="/no-such-path"
              # -DSTANDARD_UTILS_PATH="/no-such-path"
              # This creates a bash closer to a normal FHS distro bash.
              # Somewhere in the android build system >= android 12, bash starts
              # inside an environment with PATH unset, and it gets "/no-such-path"
              # Command: env -i bash -c 'echo $PATH'
              # On NixOS/nixpkgs it outputs:  /no-such-path
              # On normal distros it outputs: /usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:.
              NIX_CFLAGS_COMPILE = ''
                -DSYS_BASHRC="/etc/bashrc"
                -DSYS_BASH_LOGOUT="/etc/bash_logout"
                -DNON_INTERACTIVE_LOGIN_SHELLS
                -DSSH_SOURCE_BASHRC
              '';
            });
          });
        buildFHSUserEnv = if (config.androidVersion >= 12) then patchedPkgs.buildFHSUserEnv else pkgs.buildFHSUserEnv;
      in buildFHSUserEnv {
        name = "robotnix-build";
        targetPkgs = pkgs: config.envPackages;
        multiPkgs = pkgs: with pkgs; [ zlib ];

        # TODO might not be needed in the future, required now because
        # Android works in mysterious ways. Wasn't needed in the past
        # because these paths were already a part of LD_LIBRARY_PATH
        # when using FHS.
        #
        # See here for issue when it was introduced https://github.com/NixOS/nixpkgs/issues/262775
        # Inspiration taken from here https://github.com/NixOS/nixpkgs/pull/278361
        # More information here as well https://github.com/NixOS/nixpkgs/issues/103648
        profile = ''
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib:/usr/lib32
        '';
      };
    };
  }];
}
