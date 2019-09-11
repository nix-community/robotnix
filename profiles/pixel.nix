{ config, pkgs, lib, ... }:

with lib;
let
  # TODO: Autogenerate this list in a json file.
  img = {
    marlin."9" = {
      url = "https://dl.google.com/dl/android/aosp/marlin-pq3a.190801.002-factory-13dbb265.zip";
      sha256 = "13dbb265fb7ab74473905705d2e34d019ffc0bae601d1193e71661133aba9653";
    };
    marlin."10" = {
      url = "https://dl.google.com/dl/android/aosp/marlin-qp1a.190711.020-factory-2db5273a.zip";
      sha256 = "2db5273a273a491fee3e175f3018830fc58015bdbacfedb589d67acf123156f8";
    };
    crosshatch."9" = {
      url = "https://dl.google.com/dl/android/aosp/crosshatch-pq3a.190801.002-factory-15db810d.zip";
      sha256 = "15db810de7d3aa3ad660ffe6bcd572178c8d7c3fa363fef308cde29e0225b6c1";
    };
    crosshatch."10" = {
      url = "https://dl.google.com/dl/android/aosp/crosshatch-qp1a.190711.020-factory-2eae0727.zip";
      sha256 = "2eae0727565dc516a60e05f8502671d24e6d4b25770618d83d8a763147e259d3";
    };
  };
in
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
    kernel.clangVersion = mkDefault {
      "9" = "4393122";
      "10" = "r349610";
    }.${config.androidVersion};
    kernel.compiler = mkDefault "clang";
    vendor.img = mkDefault (pkgs.fetchurl img.${config.deviceFamily}.${config.androidVersion});
  }

  # Device-specific overrides
  (mkIf (config.deviceFamily == "marlin") {
    kernel.compiler = "gcc";
    avbMode = mkDefault "verity_only";
  })
  (mkIf (config.deviceFamily == "taimen") {
    kernel.configName = "wahoo";
    kernel.relpath = "device/google/wahoo-kernel";
    avbMode = mkDefault "vbmeta_simple";
  })
  (mkIf (config.deviceFamily == "crosshatch") {
    kernel.configName = "b1c1";
    avbMode = mkDefault "vbmeta_chained";
  })
  (mkIf (config.deviceFamily == "bonito") {
    avbMode = mkDefault "vbmeta_chained";
  })
]
