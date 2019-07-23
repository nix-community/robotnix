{ config, pkgs, lib, ... }:

with lib;
let
  kernelConfigName = {
    marlin = "marlin";
    taimen = "wahoo";
    crosshatch = "b1c1";
  }.${config.deviceFamily};
  prebuiltGCC = pkgs.stdenv.mkDerivation {
    name = "prebuilt-gcc";
    src = config.source.dirs."prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9".contents;
    nativeBuildInputs = with pkgs; [ python autoPatchelfHook ];
    installPhase = ''
      cp -r $src $out
    '';
  };
in
{
  options = {
    kernel.lz4-dtb = mkOption {
      type = types.path;
    };

    kernel.src = mkOption {
      default = null;
      type = types.path;
    };
  };

  config = {
    kernel.lz4-dtb = mkDefault (pkgs.stdenv.mkDerivation {
      name = "kernel-${config.device}-Image.lz4-dtb";
      inherit (config.kernel) src;

      postPatch = lib.optionalString (config.deviceFamily == "marlin") ''
        openssl x509 -outform der -in ${config.certs.verity.x509} -out verity_user.der.x509
      '';

      nativeBuildInputs = with pkgs; [ perl bc nettools openssl rsync gmp libmpc mpfr lz4 ];

      enableParallelBuilding = true;
      makeFlags = [
        "ARCH=arm64"
        "CONFIG_COMPAT_VDSO=n"
        "CROSS_COMPILE=${prebuiltGCC}/bin/aarch64-linux-android-"
      ];

      preBuild = ''
        make ARCH=arm64 ${kernelConfigName}_defconfig
      '';

      installPhase = ''
        cp arch/arm64/boot/Image.lz4-dtb $out
      '';
    });
  };
}
