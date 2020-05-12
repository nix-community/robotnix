{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.kernel;
  prebuiltGCC = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc";
    src = config.source.dirs."prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9".src;
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r . $out
    '';
  };
  prebuiltGCCarm32 = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc-arm32";
    src = config.source.dirs."prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9".src;
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r . $out
    '';
  };
  prebuiltClang = pkgs.stdenv.mkDerivation {
    name = "prebuilt-clang";
    src = config.source.dirs."prebuilts/clang/host/linux-x86".src + "/clang-${cfg.clangVersion}";
    buildInputs = with pkgs; [ python autoPatchelfHook zlib ncurses5 libedit stdenv.cc.cc.lib ]; # Include cc.lib for libstdc++.so.6
    installPhase = ''
      cp -r . $out
      cp ${pkgs.libedit}/lib/libedit.so.0 $out/lib64/libedit.so.2 # ABI is the same--but distros have inconsistent numbering
    '';
  };
  prebuiltMisc = pkgs.stdenv.mkDerivation {
    name = "prebuilt-misc";
    src = config.source.dirs."prebuilts/misc".src;
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      mkdir -p $out/bin
      cp linux-x86/dtc/* $out/bin
      cp linux-x86/libufdt/* $out/bin
    '';
  };
in
{
  options = {
    kernel = {
      useCustom = mkOption {
        default = false;
        type = types.bool;
      };

      name = mkOption {
        internal = true;
        type = types.str;
      };

      configName = mkOption {
        internal = true;
        type = types.str;
      };

      src = mkOption {
        type = types.path;
      };

      patches = mkOption {
        default = [];
        type = types.listOf types.path;
      };

      postPatch = mkOption {
        default = "";
        type = types.lines;
      };

      relpath = mkOption {
        type = types.str;
        description = "Relative path in source tree to place kernel build artifacts";
      };

      compiler = mkOption {
        default = "gcc";
        type = types.strMatching "(gcc|clang)";
      };

      clangVersion = mkOption {
        type = types.str;
        description = "Version of prebuilt clang to use for kernel. See https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/master/README.md";
      };

      buildProductFilenames = mkOption {
        type = types.listOf types.str;
        description = "list of build products in kernel out/ to copy into relpath";
      };
    };
  };

  config = {
    kernel.name = mkOptionDefault config.deviceFamily;
    kernel.relpath = mkOptionDefault "device/google/${config.kernel.name}-kernel";

    kernel.postPatch = lib.optionalString (config.signBuild && (config.avbMode == "verity_only")) ''
      rm -f verity_*.x509
      openssl x509 -outform der -in ${config.build.x509 "verity"} -out verity_user.der.x509
    '';

    build.kernel = pkgs.stdenv.mkDerivation {
      name = "kernel-${cfg.name}";
      inherit (cfg) src patches postPatch;

      # From os-specific/linux/kernel/manual-config.nix in nixpkgs
      prePatch = ''
        for mf in $(find -name Makefile -o -name Makefile.include -o -name install.sh); do
            echo "stripping FHS paths in \`$mf'..."
            sed -i "$mf" -e 's|/usr/bin/||g ; s|/bin/||g ; s|/sbin/||g'
        done
        sed -i scripts/ld-version.sh -e "s|/usr/bin/awk|${pkgs.gawk}/bin/awk|"
      '';

      nativeBuildInputs = with pkgs; [
        perl bc nettools openssl rsync gmp libmpc mpfr lz4
        prebuiltGCC prebuiltGCCarm32 prebuiltMisc
      ] ++ lib.optionals (cfg.compiler == "clang") [ prebuiltClang pkgsCross.aarch64-multiplatform.buildPackages.binutils ];  # TODO: Generalize to other arches

      enableParallelBuilding = true;
      makeFlags = [
        "O=out"
        "ARCH=arm64"
        "CONFIG_COMPAT_VDSO=n"
        "CROSS_COMPILE=aarch64-linux-android-"
        #"CROSS_COMPILE_ARM32=arm-linux-androideabi-"
      ] ++ lib.optionals (cfg.compiler == "clang") [
        "CC=clang"
        "CLANG_TRIPLE=aarch64-unknown-linux-gnu-" # This should match the prefix being produced by pkgsCross.aarch64-multiplatform.buildPackages.binutils. TODO: Generalize to other arches
      ];

      preBuild = ''
        # (from nixpkgs) Note: we can get rid of this once http://permalink.gmane.org/gmane.linux.kbuild.devel/13800 is merged.
        buildFlagsArray+=("KBUILD_BUILD_TIMESTAMP=$(date -u -d @$SOURCE_DATE_EPOCH)")

        make O=out ARCH=arm64 ${cfg.configName}_defconfig
      '' + optionalString (cfg.compiler == "clang") ''
        export LD_LIBRARY_PATH="${prebuiltClang}/lib:$LD_LIBRARY_PATH"
      ''; # So it can load LLVMgold.so

      installPhase = ''
        mkdir -p $out
      '' + (concatMapStringsSep "\n" (filename: "cp out/${filename} $out/") cfg.buildProductFilenames);
    };

    source.dirs = mkIf cfg.useCustom {
      ${cfg.relpath}.enable = false;
    };
    source.unpackScript = mkIf cfg.useCustom ''
      mkdir -p ${cfg.relpath}
      cp -fv ${config.build.kernel}/* ${cfg.relpath}/
      chmod -R u+w ${cfg.relpath}/
    '';
  };
}
