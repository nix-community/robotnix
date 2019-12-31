{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.kernel;
  prebuiltGCC = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc";
    src = config.source.dirs."prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9".contents;
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r . $out
    '';
  };
  prebuiltGCCarm32 = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc-arm32";
    src = config.source.dirs."prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9".contents;
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r . $out
    '';
  };
  prebuiltClang = pkgs.stdenv.mkDerivation {
    name = "prebuilt-clang";
    src = config.source.dirs."prebuilts/clang/host/linux-x86".contents + "/clang-${cfg.clangVersion}";
    buildInputs = with pkgs; [ python autoPatchelfHook zlib ncurses5 libedit stdenv.cc.cc.lib ]; # Include cc.lib for libstdc++.so.6
    installPhase = ''
      cp -r . $out
      cp ${pkgs.libedit}/lib/libedit.so.0 $out/lib64/libedit.so.2 # ABI is the same--but distros have inconsistent numbering
    '';
  };
  prebuiltMisc = pkgs.stdenv.mkDerivation {
    name = "prebuilt-misc";
    src = config.source.dirs."prebuilts/misc".contents;
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
    build.kernel = pkgs.stdenv.mkDerivation {
      name = "kernel-${config.device}";
      inherit (config.kernel) src;

      # From os-specific/linux/kernel/manual-config.nix in nixpkgs
      prePatch = ''
        for mf in $(find -name Makefile -o -name Makefile.include -o -name install.sh); do
            echo "stripping FHS paths in \`$mf'..."
            sed -i "$mf" -e 's|/usr/bin/||g ; s|/bin/||g ; s|/sbin/||g'
        done
        sed -i scripts/ld-version.sh -e "s|/usr/bin/awk|${pkgs.gawk}/bin/awk|"
      '';

      patches = config.kernel.patches;

      postPatch = lib.optionalString (config.signBuild && (config.avbMode == "verity_only")) ''
        rm -f verity_*.x509
        openssl x509 -outform der -in ${config.build.x509 "verity"} -out verity_user.der.x509
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
        make O=out ARCH=arm64 ${config.kernel.configName}_defconfig
      '' + optionalString (cfg.compiler == "clang") ''
        export LD_LIBRARY_PATH="${prebuiltClang}/lib:$LD_LIBRARY_PATH"
      ''; # So it can load LLVMgold.so

      installPhase = ''
        mkdir -p $out
      '' + (concatMapStringsSep "\n" (filename: "cp out/${filename} $out/") cfg.buildProductFilenames);
    };

    source.dirs = mkIf config.kernel.useCustom {
      ${config.kernel.relpath}.enable = false;
    };
    source.unpackScript = mkIf config.kernel.useCustom ''
      mkdir -p ${config.kernel.relpath}
      cp -fv ${config.build.kernel}/* ${config.kernel.relpath}/
      chmod -R u+w ${config.kernel.relpath}/
    '';
  };
}
