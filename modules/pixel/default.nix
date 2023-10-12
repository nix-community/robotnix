# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkMerge mkDefault mkOptionDefault;

  imgList = lib.importJSON ./pixel-imgs.json;
  otaList = lib.importJSON ./pixel-otas.json;
  fetchItem = json:
    let
      matchingItem = lib.findSingle
        (v: (v.device == config.device) && (lib.hasInfix "(${config.apv.buildID}," v.version)) # Look for left paren + upstream buildNumber + ","
        (throw "no items found for vendor img/ota")
        (throw "multiple items found for vendor img/ota")
        json;
    in
    pkgs.fetchurl (lib.filterAttrs (n: v: (n == "url" || n == "sha256")) matchingItem);

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
    barbet = { family = "barbet"; name = "Pixel 5a (5G)"; };
    raven = { family = "raviole"; name = "Pixel 6 Pro"; };
    oriole = { family = "raviole"; name = "Pixel 6"; };
    bluejay = { family = "bluejay"; name = "Pixel 6a"; };
    panther = { family = "pantah"; name = "Pixel 7"; };
    cheetah = { family = "pantah"; name = "Pixel 7 Pro"; };
  };

  # Make a uuid based on some string data
  uuidgen = str:
    let
      hash = builtins.hashString "sha256" str;
      s = i: len: lib.substring i len hash;
    in
    lib.toLower "${s 0 8}-${s 8 4}-${s 12 4}-${s 16 4}-${s 20 12}";

  # UUID for persist.img
  uuid = uuidgen "persist-${config.buildNumber}-${builtins.toString config.buildDateTime}";
  hashSeed = uuidgen "persist-hash-${config.buildNumber}-${builtins.toString config.buildDateTime}";
in
mkMerge [
  (mkIf ((lib.elem config.flavor [ "vanilla" "grapheneos" ]) && (config.device != null) && (lib.hasAttr config.device deviceMap)) {
    # Default settings that apply to all devices unless overridden. TODO: Make conditional
    deviceFamily = mkDefault (deviceMap.${config.device}.family or config.device);
    deviceDisplayName = mkDefault (deviceMap.${config.device}.name or config.device);
    arch = mkDefault "arm64";

    apv.img = mkDefault (fetchItem imgList);
    apv.ota = mkDefault (fetchItem otaList);

    # Exclude all devices by default
    # source.excludeGroups = mkDefault (lib.attrNames deviceMap);
    # # But include names related to our device
    # source.includeGroups = mkDefault [ config.device config.deviceFamily ];

    signing.avb.enable = mkDefault true;
  })

  # Device-specific overrides
  (mkIf (config.deviceFamily == "marlin") {
    signing.avb.mode = "verity_only";
    signing.apex.enable = false; # Upstream forces "TARGET_FLATTEN_APEX := false" anyway
  })
  (mkIf (lib.elem config.deviceFamily [ "taimen" "muskie" ]) {
    signing.avb.mode = "vbmeta_simple";
  })
  (mkIf (config.deviceFamily == "crosshatch") {
    signing.avb.mode = "vbmeta_chained";
    retrofit = mkIf (config.androidVersion >= 10) (mkDefault true);

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
  (mkIf (lib.elem config.deviceFamily [ "coral" "sunfish" "redfin" "barbet" ]) {
    signing.avb.mode = "vbmeta_chained_v2";
  })
  (mkIf (config.deviceFamily == "sunfish" && config.androidVersion >= 12) {
    signing.apex.packageNames = [ "com.android.vibrator.sunfish" ];
  })
  (mkIf (lib.elem config.deviceFamily [ "bonito" "sunfish" "redfin" "barbet" ] && config.androidVersion >= 12) {
    signing.apex.packageNames = [ "com.android.vibrator.drv2624" ];
  })
]
