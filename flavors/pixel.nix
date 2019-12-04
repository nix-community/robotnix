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

  deviceFamilyMap = {
    marlin = "marlin"; # Pixel XL
    sailfish = "marlin"; # Pixel
    taimen = "taimen"; # Pixel 2 XL
    walleye = "taimen"; # Pixel 2
    crosshatch = "crosshatch"; # Pixel 3 XL
    blueline = "crosshatch"; # Pixel 3
    bonito = "bonito"; # Pixel 3a XL
    sargo = "bonito"; # Pixel 3a
    coral = "coral"; # Pixel 4 XL
    flame = "coral"; # Pixel 4
  };

  kernelName = if (config.deviceFamily == "taimen") then "wahoo" else config.deviceFamily;
in
mkMerge [
  (mkIf (hasAttr config.device deviceFamilyMap) { # Default settings that apply to all devices unless overridden. TODO: Make conditional
    deviceFamily = mkDefault deviceFamilyMap.${config.device};

    kernel.configName = mkDefault config.deviceFamily;
    kernel.relpath = mkDefault "device/google/${kernelName}-kernel";
    vendor.img = mkDefault (latestImg config.device (toString config.androidVersion));
    vendor.ota = mkDefault (latestOta config.device (toString config.androidVersion));

    source.excludeGroups = mkDefault [
      # Exclude all devices by default
      "marlin" "muskie" "wahoo" "taimen" "crosshatch" "bonito" "coral"
    ];
    source.includeGroups = mkDefault [ config.deviceFamily config.kernel.configName ];
  })

  # Device-specific overrides
  (mkIf (config.deviceFamily == "marlin") {
    kernel.compiler = "gcc";
    avbMode = "verity_only";
    apex.enable = false; # Upstream forces "TARGET_FLATTEN_APEX := false" anyway
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4-dtb"
    ];
  })
  (mkIf (config.deviceFamily == "taimen") {
    avbMode = "vbmeta_simple";
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4-dtb"
      "arch/arm64/boot/dtbo.img"
    ];
  })
  (mkIf (config.deviceFamily == "crosshatch") {
    kernel.configName = "b1c1";
    avbMode = "vbmeta_chained";
    retrofit = mkIf (config.androidVersion >= 10) (mkDefault true);
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/qcom/sdm845-v2.dtb"
      "arch/arm64/boot/dts/qcom/sdm845-v2.1.dtb"
    ];
  })
  (mkIf (config.deviceFamily == "bonito") {
    avbMode = "vbmeta_chained";
    retrofit = mkIf (config.androidVersion >= 10) (mkDefault true);
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/qcom/sdm670.dtb"
    ];
  })
]
