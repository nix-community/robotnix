{ config, pkgs, lib, ... }:

with lib;
let
  flex = pkgs.callPackage ../misc/flex-2.5.39.nix {};
in
mkMerge [
{
  source.hashes = importJSON ./hashes.json;

  # Some android version-specific fixes:
  source.dirs."prebuilts/misc".postPatch = mkIf (config.androidVersion == 9) "ln -sf ${flex}/bin/flex linux-x86/flex/flex-2.5.39";
  source.dirs."build/make".patches = mkIf (config.androidVersion == 10) [
    ../patches/10/readonly-fix.patch
    (pkgs.substituteAll {
      src = ../patches/10/partition-size-fix.patch;
      inherit (pkgs) coreutils;
    })
  ];

  source.excludeGroups = mkDefault [
    "darwin" # Linux-only for now
    "mips" "hikey"
  ];
  source.includeGroups = mkIf (config.deviceFamily != null) (mkDefault [ config.deviceFamily ]);

  kernel.compiler = mkDefault "clang";
  kernel.clangVersion = mkDefault {
    "9" = "4393122";
    "10" = "r349610";
  }.${toString config.androidVersion};
  apex.enable = mkIf (config.androidVersion >= 10) (mkDefault true);
}
{
  # Disable some unused directories to save time downloading / extracting
  source.dirs = listToAttrs (map (dir: nameValuePair dir { enable = false; })
    [ "developers/samples/android"
      "developers/demos"

      "device/generic/car"
#      "device/generic/qemu"
#      "prebuilts/qemu-kernel"
      "prebuilts/android-emulator"

      "device/linaro/bootloader/arm-trusted-firmware"
      "device/linaro/bootloader/edk2"
      "device/linaro/bootloader/OpenPlatformPkg"
      "device/linaro/hikey"
      "device/linaro/hikey-kernel"
      "device/linaro"

      "device/generic/mini-emulator-arm64"
      "device/generic/mini-emulator-armv7-a-neon"
      "device/generic/mini-emulator-mips"
      "device/generic/mini-emulator-mips64"
      "device/generic/mini-emulator-x86"
      "device/generic/mini-emulator-x86_64"
      "device/generic/mips"
      "device/generic/mips64"
      "device/google/accessory/arduino"
      "device/google/accessory/demokit"
      "device/google/atv"
    ]);
}]
