{ config, pkgs, lib, ... }:

with lib;
let
  prebuiltGCC = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc";
    src = config.build.sourceDir "prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9";
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r . $out
    '';
  };
  prebuiltGCCarm32 = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc-arm32";
    src = config.build.sourceDir "prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9";
    buildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r . $out
    '';
  };
  prebuiltClang = pkgs.stdenv.mkDerivation {
    name = "prebuilt-clang";
    src = (config.build.sourceDir "prebuilts/clang/host/linux-x86") + /clang-4393122; # Parameterize this number?
    buildInputs = with pkgs; [ python autoPatchelfHook zlib ncurses5 libedit ];
    installPhase = ''
      cp -r . $out
      cp ${pkgs.libedit}/lib/libedit.so.0 $out/lib64/libedit.so.2 # ABI is the same--but distros have inconsistent numbering
    '';
  };
  prebuiltMisc = pkgs.stdenv.mkDerivation {
    name = "prebuilt-misc";
    src = config.build.sourceDir "prebuilts/misc";
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
      configName = mkOption {
        default = {
          marlin = "marlin";
          taimen = "wahoo";
          crosshatch = "b1c1";
        }.${config.deviceFamily};
        type = types.str;
      };

      src = mkOption {
        default = null;
        type = types.nullOr types.path;
      };

      patches = mkOption {
        default = [];
        type = types.listOf types.path;
      };

      relpath = mkOption {
        default = "device/google/${replaceStrings [ "taimen" ] [ "wahoo" ] config.deviceFamily}-kernel";
        type = types.str;
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

      postPatch = lib.optionalString (config.deviceFamily == "marlin") ''
        openssl x509 -outform der -in ${config.certs.verity.x509} -out verity_user.der.x509
      '';

      nativeBuildInputs = with pkgs; [
        perl bc nettools openssl rsync gmp libmpc mpfr lz4
        prebuiltGCC prebuiltGCCarm32 prebuiltMisc
      ] ++ lib.optionals (config.deviceFamily != "marlin") [ prebuiltClang pkgsCross.aarch64-multiplatform.buildPackages.binutils ];

      enableParallelBuilding = true;
      makeFlags = [
        "ARCH=arm64"
        "CONFIG_COMPAT_VDSO=n"
        "CROSS_COMPILE=aarch64-linux-android-"
        #"CROSS_COMPILE_ARM32=arm-linux-androideabi-"
      ] ++ lib.optionals (config.deviceFamily != "marlin") [
        "CC=clang"
        "CLANG_TRIPLE=aarch64-unknown-linux-gnu-" # This should match the prefix being produced by pkgsCross.aarch64-multiplatform.buildPackages.binutils
      ];

      preBuild = ''
        make ARCH=arm64 ${config.kernel.configName}_defconfig
      '' + optionalString (config.deviceFamily != "marlin") ''
        export LD_LIBRARY_PATH="${prebuiltClang}/lib:$LD_LIBRARY_PATH"
      ''; # So it can load LLVMgold.so

      installPhase = ''
        mkdir -p $out
        cp arch/arm64/boot/Image.lz4-dtb $out/
      '' + optionalString (config.deviceFamily != "marlin") ''
        cp arch/arm64/boot/dtbo.img $out/
      '';
    };

    postPatch = mkIf (config.kernel.src != null) ''
      rm -rf ${config.kernel.relpath}
      mkdir -p ${config.kernel.relpath}
      cp -v ${config.build.kernel}/* ${config.kernel.relpath}/
      chmod -R u+w ${config.kernel.relpath}/
    '';
  };
}
