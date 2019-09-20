{ config, pkgs, lib, ... }:

with lib;
let
  imgList = builtins.fromJSON (builtins.readFile ./pixel-imgs.json);
  latestImg = device: version: let
    matchingImgs = filter (v: (v.device == device) && (hasPrefix version v.version)) imgList;
  in
    # This assumes that the last machine entry is the latest--which should hold from the website
    pkgs.fetchurl (filterAttrs (n: v: (n == "url" || n == "sha256")) (elemAt matchingImgs ((length matchingImgs)-1)));

  # TODO: unify logic with above
  otaList = builtins.fromJSON (builtins.readFile ./pixel-otas.json);
  latestOta = device: version: let
    matchingOtas = filter (v: (v.device == device) && (hasPrefix version v.version)) otaList;
  in
    pkgs.fetchurl (filterAttrs (n: v: (n == "url" || n == "sha256")) (elemAt matchingOtas ((length matchingOtas)-1)));
in
mkMerge [
  { # Default settings that apply to all devices unless overridden. TODO: Make conditional
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
    vendor.img = mkDefault (latestImg config.device config.androidVersion);
    vendor.ota = mkDefault (latestOta config.device config.androidVersion);
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
