{ config, pkgs, lib, ... }:

with lib;
mkMerge [
  { # Default settings that apply to all devices unless overridden.
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

    kernel.configName = mkDefault config.deviceFamily;
    kernel.relpath = mkDefault "device/google/${config.deviceFamily}-kernel";
    kernel.clangVersion = mkDefault "r349610";
    kernel.compiler = mkDefault "clang";
  }

  # Device-specific overrides
  (mkIf (config.deviceFamily == "marlin") {
    kernel.compiler = "gcc";
    avbMode = mkDefault "verity_only";
    vendor.img = mkDefault (pkgs.fetchurl {
      url = "https://dl.google.com/dl/android/aosp/marlin-pq3a.190801.002-factory-13dbb265.zip";
      sha256 = "13dbb265fb7ab74473905705d2e34d019ffc0bae601d1193e71661133aba9653";
    });
  })
  (mkIf (config.deviceFamily == "taimen") {
    kernel.configName = "wahoo";
    kernel.relpath = "device/google/wahoo-kernel";
    avbMode = mkDefault "vbmeta_simple";
  })
  (mkIf (config.deviceFamily == "crosshatch") {
    kernel.configName = "b1c1";
    avbMode = mkDefault "vbmeta_chained";
    vendor.img = mkDefault (pkgs.fetchurl {
      url = "https://dl.google.com/dl/android/aosp/crosshatch-pq3a.190801.002-factory-15db810d.zip";
      sha256 = "15db810de7d3aa3ad660ffe6bcd572178c8d7c3fa363fef308cde29e0225b6c1";
    });
  })
  (mkIf (config.deviceFamily == "bonito") {
    avbMode = mkDefault "vbmeta_chained";
  })
]
