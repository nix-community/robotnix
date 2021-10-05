# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

# TODO: remove all the redfin exceptions
# TODO: Replace with a solution for https://github.com/danielfullmer/robotnix/issues/116

{ config, pkgs, lib, ... }:

let
  inherit (lib)
    elem optional optionals optionalAttrs
    mkIf mkOption mkOptionDefault mkDefault mkMerge mkEnableOption types;

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

  configName = {
    "taimen" = "wahoo";
    "muskie" = "wahoo";
    "crosshatch" = "b1c1";
    "coral" = "floral";
    "redfin" =  "redbull";
  }.${config.deviceFamily} or config.deviceFamily;
  compiler = if (elem config.deviceFamily == "marlin") then "gcc" else "clang";
  linker = if (elem config.deviceFamily [ "coral" "sunfish" ]) then "lld" else "gold";

  installModules = !(elem config.deviceFamily [ "marlin" "taimen" "muskie" ]);

  buildProductFilenames =
    optional installModules "moduleout/**/*.ko"
    ++ optionals (config.deviceFamily == "marlin") [
      "arch/arm64/boot/Image.lz4-dtb"
    ] ++ optionals (elem config.deviceFamily [ "taimen" "muskie" ]) [
      "arch/arm64/boot/Image.lz4-dtb"
      "arch/arm64/boot/dtbo.img"
    ] ++ optionals (config.deviceFamily == "crosshatch") [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/qcom/sdm845-v2.dtb"
      "arch/arm64/boot/dts/qcom/sdm845-v2.1.dtb"
    ] ++ optionals (config.deviceFamily == "bonito") [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/qcom/sdm670.dtb"
    ] ++ optionals (config.deviceFamily == "coral") [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/google/qcom-base/sm8150.dtb"
      "arch/arm64/boot/dts/google/qcom-base/sm8150-v2.dtb"
    ] ++ optionals (config.deviceFamily == "sunfish") [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/google/qcom-base/sdmmagpie.dtb"
    ] ++ optionals (config.deviceFamily == "redfin") [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/google/qcom-base/lito.dtb"
    ] ++ optionals (config.deviceFamily == "barbet") [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/google/qcom-base/lito.dtb"
    ];

  postRedfin = lib.elem config.deviceFamily [ "redfin" "barbet" ];

  kernel = pkgs.stdenv.mkDerivation ({
    name = "vanilla-${configName}-kernel";
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
    ++ lib.optionals (compiler == "clang") [ prebuiltClang ]  # TODO: Generalize to other arches
    ++ lib.optionals (!postRedfin) [ prebuiltGCC prebuiltGCCarm32 ]
    ++ lib.optionals postRedfin [
      # HACK: Additional dependencies needed by redfin.
      python bison flex cpio
      prebuiltGas
    ]
    # needed for `depmod`, used in modules_install
    ++ lib.optional installModules kmod;

    enableParallelBuilding = true;
    makeFlags = [
      "O=out"
      "ARCH=arm64"
      #"CONFIG_COMPAT_VDSO=n"
    ] ++ (
      if postRedfin
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
      ] ++ lib.optionals (compiler == "clang") [
        "CC=clang"
        "CLANG_TRIPLE=aarch64-unknown-linux-gnu-" # This should match the prefix being produced by pkgsCross.aarch64-multiplatform.buildPackages.binutils. TODO: Generalize to other arches
      ] ++ lib.optional (linker == "lld") [
        # Otherwise fails with  aarch64-linux-android-ld.gold: error: arch/arm64/lib/lib.a: member at 4210 is not an ELF object
        "LD=ld.lld"
      ])
    );

    preBuild = ''
      buildFlagsArray+=("KBUILD_BUILD_TIMESTAMP=$(date -u -d @${builtins.toString cfg.buildDateTime})")

      buildFlagsArray+=("KBUILD_BUILD_VERSION=1")

      make O=out ARCH=arm64 ${configName}_defconfig
    '' + lib.optionalString (compiler == "clang") ''
      export LD_LIBRARY_PATH="${prebuiltClang}/lib:$LD_LIBRARY_PATH"
    ''; # So it can load LLVMgold.so

    # Strip modules
    postBuild = lib.optionalString installModules ''
      make $makeFlags "''${makeFlagsArray[@]}" INSTALL_MOD_PATH=moduleout INSTALL_MOD_STRIP=1 modules_install
    '';

    installPhase = ''
      mkdir -p $out
      shopt -s globstar nullglob
      ${lib.optionalString postRedfin "cp out/arch/arm64/boot/dtbo_${config.device}.img out/arch/arm64/boot/dtbo.img"}
    '' + (lib.concatMapStringsSep "\n" (filename: "cp out/${filename} $out/") buildProductFilenames)
    + ''

      # This is also done in nixpkgs for wireless modules
      nuke-refs $(find $out -name "*.ko")
    '';

    dontFixup = true;
    dontStrip = true;
  } // lib.optionalAttrs (lib.elem config.deviceFamily [ "coral" "sunfish" "redfin" "barbet" ]) {
    # HACK: Needed for coral (pixel 4) (Don't turn this on for other devices)
    DTC_EXT = "${prebuiltMisc}/bin/dtc";
    DTC_OVERLAY_TEST_EXT = "${prebuiltMisc}/bin/ufdt_apply_overlay";
  });

in mkIf (config.flavor == "vanilla" && config.kernel.enable) {
  # TODO: Could extract the bind-mounting thing in source.nix into something
  # that works for kernels too. Probably not worth the effort for the payoff
  # though.
  kernel.src = let
    kernelName = if elem config.deviceFamily [ "taimen" "muskie"] then "wahoo" else config.deviceFamily;
    kernelMetadata = (lib.importJSON ./kernel-metadata.json).${kernelName};
    kernelRepos = lib.importJSON (./. + "/repo-${kernelMetadata.branch}.json");
    fetchRepo = repo: pkgs.fetchgit {
      inherit (kernelRepos.${repo}) url rev sha256;
    };
    kernelDirs = {
      "" = fetchRepo "private/msm-google";
    } // optionalAttrs (elem kernelName [ "crosshatch" "bonito" "coral" "sunfish" "redfin" ]) {
      "techpack/audio" = fetchRepo "private/msm-google/techpack/audio";
      "drivers/staging/qca-wifi-host-cmn" = fetchRepo "private/msm-google-modules/wlan/qca-wifi-host-cmn";
      "drivers/staging/qcacld-3.0" = fetchRepo "private/msm-google-modules/wlan/qcacld-3.0";
      "drivers/staging/fw-api" = fetchRepo "private/msm-google-modules/wlan/fw-api";
    } // optionalAttrs (elem kernelName [ "coral" "sunfish" ]) {
      # Sunfish previously used a fts_touch_s5 repo, but it's tag moved back to
      # to regular fts_touch repo, however, the kernel manifest was not updated.
      "drivers/input/touchscreen/fts_touch" = fetchRepo "private/msm-google-modules/touch/fts/floral";
    } // optionalAttrs (elem kernelName [ "redfin" ]) { # TODO: barbet? it's currently set to kernel.enable=false;
      "drivers/input/touchscreen/fts_touch" = fetchRepo "private/msm-google-modules/touch/fts";

      "techpack/audio" = fetchRepo "private/msm-google/techpack/audio";
      "techpack/camera" = fetchRepo "private/msm-google/techpack/camera";
      "techpack/dataipa" = fetchRepo "private/msm-google/techpack/dataipa";
      "techpack/display" = fetchRepo "private/msm-google/techpack/display";
      "techpack/video" = fetchRepo "private/msm-google/techpack/video";
      "drivers/input/touchscreen/sec_touch" = fetchRepo "private/msm-google-modules/touch/sec";
      "arch/arm64/boot/dts/vendor" = fetchRepo "private/msm-google/arch/arm64/boot/dts/vendor";
      "arch/arm64/boot/dts/vendor/qcom/camera" = fetchRepo "private/msm-google/arch/arm64/boot/dts/vendor/qcom/camera";
      "arch/arm64/boot/dts/vendor/qcom/display" = fetchRepo "private/msm-google/arch/arm64/boot/dts/vendor/qcom/display";
    };
  in pkgs.runCommand "kernel-src" {}
    (lib.concatStringsSep "\n" (lib.mapAttrsToList (relpath: repo: ''
      ${lib.optionalString (relpath != "") "mkdir -p $out/$(dirname ${relpath})"}
      cp -r ${repo} $out/${relpath}
      chmod u+w -R $out/${relpath}
    '') kernelDirs));

  kernel.relpath = let
      kernelName =  if elem config.deviceFamily [ "taimen" "muskie"] then "wahoo" else config.deviceFamily;
  in mkDefault "device/google/${kernelName}-kernel";

  build.kernel = kernel;
}
