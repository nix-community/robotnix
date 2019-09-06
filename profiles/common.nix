{ config, pkgs, lib, ... }:

with lib;
let
  flex = pkgs.callPackage ../misc/flex-2.5.39.nix {};
in
{
  # Android 9: Fix a locale issue with included flex program
  source.postPatch = "ln -sf ${flex}/bin/flex prebuilts/misc/linux-x86/flex/flex-2.5.39";

  source.excludeGroups = mkDefault [
    "darwin" # Linux-only for now
    "mips" "hikey"
    "marlin" "muskie" "wahoo" "taimen" "crosshatch" "bonito" # Exclude all devices by default
  ];
  source.includeGroups = mkDefault [ config.device config.deviceFamily config.kernel.configName ]; # But include the one we care about. Also include deviceFamily and kernel.configName, which might be an alternate name

  # Disable some unused directories to save time downloading / extracting
  source.dirs = listToAttrs (map (dir: nameValuePair dir { enable = false; })
    [ "developers/samples/android"
      "developers/demos"

      "device/generic/car"
      "device/generic/qemu"
      "prebuilts/qemu-kernel"

      "device/generic/goldfish"
      "device/generic/goldfish-opengl"

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
      "device/google/contexthub"
      "device/google/cuttlefish"
      "device/google/cuttlefish_common"
      "device/google/cuttlefish_kernel"
      "device/google/cuttlefish_sepolicy"
      "device/google/hikey-kernel"
    ]);
}
