{ config, pkgs, lib, ... }:

with lib;
let
  imgList = lib.importJSON ./pixel-imgs.json;
  otaList = lib.importJSON ./pixel-otas.json;
  fetchItem = json: let
    matchingItem = lib.findSingle
      (v: (v.device == config.device) && (hasInfix "(${config.source.buildNumber}" v.version)) # Look for left paren + upstream buildNumber
      null
      (throw "multiple items found")
      json;
  in
    if (matchingItem == null) then null else
      pkgs.fetchurl (filterAttrs (n: v: (n == "url" || n == "sha256")) matchingItem);

  deviceFamilyMap = {
    marlin = "marlin"; # Pixel XL
    sailfish = "marlin"; # Pixel
    taimen = "taimen"; # Pixel 2 XL
    walleye = "muskie"; # Pixel 2
    crosshatch = "crosshatch"; # Pixel 3 XL
    blueline = "crosshatch"; # Pixel 3
    bonito = "bonito"; # Pixel 3a XL
    sargo = "bonito"; # Pixel 3a
    coral = "coral"; # Pixel 4 XL
    flame = "coral"; # Pixel 4
  };
  deviceFamily = deviceFamilyMap.${config.device};

  kernelName = if (config.deviceFamily == "taimen" || config.deviceFamily == "muskie") then "wahoo" else config.deviceFamily;
in
mkMerge [
  (mkIf ((config.device != null) && (hasAttr config.device deviceFamilyMap)) { # Default settings that apply to all devices unless overridden. TODO: Make conditional
    deviceFamily = mkDefault deviceFamily;
    arch = mkDefault "arm64";

    kernel.configName = mkDefault config.deviceFamily;
    kernel.relpath = mkDefault "device/google/${kernelName}-kernel";
    vendor.img = mkDefault (fetchItem imgList);
    vendor.ota = mkDefault (fetchItem otaList);

    source.excludeGroups = mkDefault [
      # Exclude all devices by default
      "marlin" "muskie" "wahoo" "taimen" "crosshatch" "bonito" "coral"
    ];
    source.includeGroups = mkDefault ([ config.device config.deviceFamily config.kernel.configName ]
      ++ (lib.optional (deviceFamily == "taimen" || deviceFamily == "muskie") "wahoo"));
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
  (mkIf (config.deviceFamily == "taimen" || config.deviceFamily == "muskie") {
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
