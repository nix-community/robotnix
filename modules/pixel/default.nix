{ config, pkgs, lib, ... }:

with lib;
let
  imgList = lib.importJSON ./pixel-imgs.json;
  otaList = lib.importJSON ./pixel-otas.json;
  fetchItem = json: let
    matchingItem = lib.findSingle
      (v: (v.device == config.device) && (hasInfix "(${config.apv.buildID}," v.version)) # Look for left paren + upstream buildNumber + ","
      (throw "no items found for vendor img/ota")
      (throw "multiple items found for vendor img/ota")
      json;
  in
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

  # Make a uuid based on some string data
  uuidgen = str: let
    hash = builtins.hashString "sha256" str;
    s = i: len: substring i len hash;
  in toLower "${s 0 8}-${s 8 4}-${s 12 4}-${s 16 4}-${s 20 12}";

  # UUID for persist.img
  uuid = uuidgen "persist-${config.buildNumber}-${builtins.toString config.buildDateTime}";
  hashSeed = uuidgen "persist-hash-${config.buildNumber}-${builtins.toString config.buildDateTime}";
in
mkMerge [
  (mkIf ((config.flavor != "lineageos") && (config.device != null) && (hasAttr config.device deviceFamilyMap)) { # Default settings that apply to all devices unless overridden. TODO: Make conditional
    deviceFamily = mkDefault deviceFamily;
    arch = mkDefault "arm64";

    kernel.name = mkIf (config.deviceFamily == "taimen" || config.deviceFamily == "muskie") (mkDefault "wahoo");
    kernel.configName = mkDefault config.deviceFamily;
    apv.img = mkIf config.apv.enable (mkDefault (fetchItem imgList));
    apv.ota = mkIf config.apv.enable (mkDefault (fetchItem otaList));

    source.excludeGroups = mkDefault [
      # Exclude all devices by default
      "marlin" "muskie" "wahoo" "taimen" "crosshatch" "bonito" "coral"
    ];
    source.includeGroups = mkDefault [ config.device config.deviceFamily config.kernel.name config.kernel.configName ];
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
  (mkIf (elem config.deviceFamily [ "taimen" "muskie" ]) {
    avbMode = "vbmeta_simple";
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4-dtb"
      "arch/arm64/boot/dtbo.img"
    ];
  })
  (mkIf (config.deviceFamily == "crosshatch") {
    avbMode = "vbmeta_chained";
    retrofit = mkIf (config.androidVersion >= 10) (mkDefault true);
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/qcom/sdm845-v2.dtb"
      "arch/arm64/boot/dts/qcom/sdm845-v2.1.dtb"
    ];

    # Reproducibility fix for persist.img.
    # TODO: Generate uuid based on fingerprint
    source.dirs."device/google/crosshatch".patches = [
      (pkgs.substituteAll {
        src = ./crosshatch-persist-img-reproducible.patch;
        inherit uuid hashSeed;
        inherit (config) buildDateTime;
      })
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

    # Reproducibility fix for persist.img.
    # TODO: Generate uuid based on fingerprint
    source.dirs."device/google/bonito".patches = [
      (pkgs.substituteAll {
        src = ./bonito-persist-img-reproducible.patch;
        inherit uuid hashSeed;
        inherit (config) buildDateTime;
      })
    ];
  })
]
