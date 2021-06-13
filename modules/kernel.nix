# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# TODO: remove all the redfin exceptions

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkOption mkOptionDefault mkMerge mkEnableOption types;

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
  prebuiltGas = let
    # Not always included in the platform repo manifest
    backupSrc = pkgs.fetchgit {
      url = "https://android.googlesource.com/platform/prebuilts/gas/linux-x86";
      rev = "592150fc8ae9f48f2e73f390961f32ca6f5f6a9f";
      sha256 = "1js9z9h89dbbzwv1pflm0026wrf5lsh3p95g86lwvagjis5xzii5";
    };
  in pkgs.stdenv.mkDerivation {
    name = "prebuilt-gas";
    src = config.source.dirs."prebuilts/gas/linux-x86".src or backupSrc;
    buildInputs = with pkgs; [ autoPatchelfHook ]; # Include cc.lib for libstdc++.so.6
    installPhase = ''
      mkdir -p $out
      cp -r . $out/bin
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

      # Needed by redfin
      cp ${config.source.dirs."system/libufdt".src}/utils/src/mkdtboimg.py $out/bin
    '';
  };
in
{
  options = {
    kernel = {
      enable = mkEnableOption "building custom kernel";

      name = mkOption {
        internal = true;
        type = types.str;
      };

      configName = mkOption {
        internal = true;
        type = types.str;
        description = ''Name of kernel configuration to build. Make builds ''${kernel.configName}_defconfig"'';
      };

      src = mkOption {
        type = types.path;
        description = "Path to kernel source";
      };

      patches = mkOption {
        default = [];
        type = types.listOf types.path;
        description = "List of patches to apply to kernel source";
      };

      postPatch = mkOption {
        default = "";
        type = types.lines;
        description = "Commands to run after patching kernel source";
      };

      relpath = mkOption {
        type = types.str;
        description = "Relative path in source tree to place kernel build artifacts";
      };

      compiler = mkOption {
        default = "clang";
        type = types.strMatching "(gcc|clang)";
        description = "Compilter to use for building kernel";
      };

      clangVersion = mkOption {
        type = types.str;
        description = ''
          Version of prebuilt clang to use for kernel.
          See https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/master/README.md"
        '';
      };

      linker = mkOption {
        default = "gold";
        type = types.strMatching "(gold|lld)";
        description = "Linker to use for building kernel";
      };

      buildProductFilenames = mkOption {
        type = types.listOf types.str;
        description = "List of build products in kernel `out/` to copy into path specified by `kernel.relpath`.";
      };
    };
  };

  config = {
    kernel.name = mkOptionDefault config.deviceFamily;
    kernel.relpath = mkOptionDefault "device/google/${config.kernel.name}-kernel";

    kernel.postPatch = lib.optionalString (config.signing.enable && (config.signing.avb.mode == "verity_only")) ''
      rm -f verity_*.x509
      openssl x509 -outform der -in ${config.signing.avb.verityCert} -out verity_user.der.x509
    '';

    build.kernel = pkgs.stdenv.mkDerivation ({
      name = "kernel-${cfg.name}";
      inherit (cfg) src patches postPatch;

      # From os-specific/linux/kernel/manual-config.nix in nixpkgs
      prePatch = ''
        for mf in $(find -name Makefile -o -name Makefile.include -o -name install.sh); do
            echo "stripping FHS paths in \`$mf'..."
            sed -i "$mf" -e 's|/usr/bin/||g ; s|/bin/||g ; s|/sbin/||g'
        done
        sed -i scripts/ld-version.sh -e "s|/usr/bin/awk|${pkgs.gawk}/bin/awk|"

        if [[ -f scripts/generate_initcall_order.pl ]]; then
          patchShebangs scripts/generate_initcall_order.pl
        fi
      '';

      nativeBuildInputs = with pkgs; [
        perl bc nettools openssl rsync gmp libmpc mpfr lz4 which
        prebuiltMisc
        nukeReferences
      ]
      ++ lib.optionals (cfg.compiler == "clang") [
        prebuiltClang
      ]  # TODO: Generalize to other arches
      ++ lib.optionals (config.deviceFamily != "redfin") [ prebuiltGCC prebuiltGCCarm32 ]
      ++ lib.optionals (config.deviceFamily == "redfin") [
        # HACK: Additional dependencies needed by redfin.
        python bison flex cpio
        prebuiltGas
        kmod # needed for `depmod`, used in modules_install
      ];

      enableParallelBuilding = true;
      makeFlags = [
        "O=out"
        "ARCH=arm64"
        #"CONFIG_COMPAT_VDSO=n"
      ] ++ (
        if (config.deviceFamily == "redfin")
        then [
          "LLVM=1"
          # Redfin kernel builds still need "gas" (GNU assembler), everything else is LLVM
          "CROSS_COMPILE=aarch64-linux-gnu-"
          "CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
          # TODO: Remove HOSTCC / HOSTCXX. Currently, removing it makes it fail:
          # ../scripts/basic/fixdep.c:97:10: fatal error: 'sys/types.h' file not found
          "HOSTCC=gcc"
          "HOSTCXX=g++"
        ]
        else ([
          "CROSS_COMPILE=aarch64-linux-android-"
          "CROSS_COMPILE_ARM32=arm-linux-androideabi-"
        ] ++ lib.optionals (cfg.compiler == "clang") [
          "CC=clang"
          "CLANG_TRIPLE=aarch64-unknown-linux-gnu-" # This should match the prefix being produced by pkgsCross.aarch64-multiplatform.buildPackages.binutils. TODO: Generalize to other arches
        ] ++ lib.optional (cfg.linker == "lld") [
          # Otherwise fails with  aarch64-linux-android-ld.gold: error: arch/arm64/lib/lib.a: member at 4210 is not an ELF object
          "LD=ld.lld"
        ])
      );

      preBuild = ''
        # (from nixpkgs) Note: we can get rid of this once http://permalink.gmane.org/gmane.linux.kbuild.devel/13800 is merged.
        buildFlagsArray+=("KBUILD_BUILD_TIMESTAMP=$(date -u -d @$SOURCE_DATE_EPOCH)")

        buildFlagsArray+=("KBUILD_BUILD_VERSION=1")

        make O=out ARCH=arm64 ${cfg.configName}_defconfig
      '' + lib.optionalString (cfg.compiler == "clang") ''
        export LD_LIBRARY_PATH="${prebuiltClang}/lib:$LD_LIBRARY_PATH"
      ''; # So it can load LLVMgold.so

      # Strip modules
      postBuild = ''
        make $makeFlags "''${makeFlagsArray[@]}" INSTALL_MOD_PATH=moduleout INSTALL_MOD_STRIP=1 modules_install
        ${lib.optionalString (config.deviceFamily == "redfin") "cp out/modules.order out/modules.load"}
      '';

      installPhase = ''
        mkdir -p $out
        shopt -s globstar nullglob
      '' + (lib.concatMapStringsSep "\n" (filename: "cp out/${filename} $out/") cfg.buildProductFilenames)
      + ''

        # This is also done in nixpkgs for wireless modules
        nuke-refs $(find $out -name "*.ko")
      '';

      dontFixup = true;
      dontStrip = true;
    } // lib.optionalAttrs (lib.elem config.deviceFamily [ "coral" "sunfish" "redfin" ]) {
      # HACK: Needed for coral (pixel 4) (Don't turn this on for other devices)
      DTC_EXT = "${prebuiltMisc}/bin/dtc";
      DTC_OVERLAY_TEST_EXT = "${prebuiltMisc}/bin/ufdt_apply_overlay";
    });

    # We have to replace files here, instead of just using the
    # config.build.kernel drv output in place of source.dirs.${cfg.relpath}.
    # This is because there are some additional things in the prebuilt kernel
    # output directory like kernel headers for sunfish under device/google/sunfish-kernel/sm7150
    source = mkIf cfg.enable {
      dirs.${cfg.relpath}.postPatch = ''
        cp -fv ${config.build.kernel}/* .
      '';
    };
  };
}
