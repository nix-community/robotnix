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

  deviceMap = {
    marlin = { family = "marlin"; name = "Pixel XL"; };
    sailfish = { family = "marlin"; name = "Pixel"; };
    taimen = { family = "taimen"; name = "Pixel 2 XL"; };
    walleye = { family = "muskie"; name = "Pixel 2"; };
    crosshatch = { family = "crosshatch"; name = "Pixel 3 XL"; };
    blueline = { family = "crosshatch"; name = "Pixel 3"; };
    bonito = { family = "bonito"; name = "Pixel 3a XL"; };
    sargo = { family = "bonito"; name = "Pixel 3a"; };
    coral = { family = "coral"; name = "Pixel 4 XL"; };
    flame = { family = "coral"; name = "Pixel 4"; };
    sunfish = { family = "sunfish"; name = "Pixel 4a"; };
    bramble = { family = "redfin"; name = "Pixel 4a (5G)"; };
    redfin = { family = "redfin"; name = "Pixel 5"; };
  };

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
  (mkIf ((config.flavor != "lineageos") && (config.device != null) && (hasAttr config.device deviceMap)) { # Default settings that apply to all devices unless overridden. TODO: Make conditional
    deviceFamily = mkDefault (deviceMap.${config.device}.family or config.device);
    deviceDisplayName = mkDefault (deviceMap.${config.device}.name or config.device);
    arch = mkDefault "arm64";

    kernel.name = mkIf (config.deviceFamily == "taimen" || config.deviceFamily == "muskie") (mkDefault "wahoo");
    kernel.configName = mkDefault config.deviceFamily;
    apv.img = mkIf config.apv.enable (mkDefault (fetchItem imgList));
    apv.ota = mkIf config.apv.enable (mkDefault (fetchItem otaList));

    # Exclude all devices by default
    source.excludeGroups = mkDefault (attrNames deviceMap);
    # But include names related to our device
    source.includeGroups = mkDefault [ config.device config.deviceFamily config.kernel.name config.kernel.configName ];

    signing.avb.enable = mkDefault true;
  })

  # Device-specific overrides
  (mkIf (config.deviceFamily == "marlin") {
    kernel.compiler = "gcc";
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4-dtb"
    ];
    signing.avb.mode = "verity_only";
    signing.apex.enable = false; # Upstream forces "TARGET_FLATTEN_APEX := false" anyway
    nixpkgs.overlays = [ (self: super: {
      android-prepare-vendor = super.android-prepare-vendor.overrideAttrs ({ patches ? [], ...}: {
        patches = patches ++ [ ../../pkgs/android-prepare-vendor/0004-marlin-sailfish-fix-build-failure.patch ];
      });
    })];
  })
  (mkIf (elem config.deviceFamily [ "taimen" "muskie" ]) {
    signing.avb.mode = "vbmeta_simple";
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4-dtb"
      "arch/arm64/boot/dtbo.img"
    ];
  })
  (mkIf (config.deviceFamily == "crosshatch") {
    signing.avb.mode = "vbmeta_chained";
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
    signing.avb.mode = "vbmeta_chained";
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
  (mkIf (config.deviceFamily == "coral") {
    signing.avb.mode = "vbmeta_chained_v2";
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/google/qcom-base/sm8150.dtb"
      "arch/arm64/boot/dts/google/qcom-base/sm8150-v2.dtb"
    ];
    kernel.configName = "floral"; # coral + flame
    kernel.linker = "lld";
  })
  (mkIf (config.deviceFamily == "sunfish") {
    signing.avb.mode = "vbmeta_chained_v2";
    kernel.buildProductFilenames = [
      "arch/arm64/boot/Image.lz4"
      "arch/arm64/boot/dtbo.img"
      "arch/arm64/boot/dts/google/qcom-base/sdmmagpie.dtb"
    ];
    kernel.linker = "lld";
  })
]
