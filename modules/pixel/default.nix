# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkMerge mkDefault mkOptionDefault;

  imgList = lib.importJSON ./pixel-imgs.json;
  otaList = lib.importJSON ./pixel-otas.json;
  fetchItem = json: let
    matchingItem = lib.findSingle
      (v: (v.device == config.device) && (lib.hasInfix "(${config.apv.buildID}," v.version)) # Look for left paren + upstream buildNumber + ","
      (throw "no items found for vendor img/ota")
      (throw "multiple items found for vendor img/ota")
      json;
  in
    pkgs.fetchurl (lib.filterAttrs (n: v: (n == "url" || n == "sha256")) matchingItem);

  deviceMap = {
    marlin = { name = "Pixel XL"; };
    sailfish = { name = "Pixel"; };
    taimen = { name = "Pixel 2 XL"; };
    walleye = { name = "Pixel 2"; };
    crosshatch = { name = "Pixel 3 XL"; };
    blueline = { name = "Pixel 3"; };
    bonito = { name = "Pixel 3a XL"; };
    sargo = { name = "Pixel 3a"; };
    coral = { name = "Pixel 4 XL"; };
    flame = { name = "Pixel 4"; };
    sunfish = { name = "Pixel 4a"; };
    bramble = { name = "Pixel 4a (5G)"; };
    redfin = { name = "Pixel 5"; };
    barbet = { name = "Pixel 5a (5G)"; };
    raven = { name = "Pixel 6 Pro"; };
    oriole = { name = "Pixel 6"; };
    bluejay = { name = "Pixel 6a"; };
    panther = { name = "Pixel 7"; };
    cheetah = { name = "Pixel 7 Pro"; };
    lynx = { name = "Pixel 7a"; };
    tangorpro = { name = "Pixel Tablet"; };
    felix = { name = "Pixel Fold"; };
    shiba = { name = "Pixel 8"; };
    husky = { name = "Pixel 8 Pro"; };
    akita = { name = "Pixel 8a"; };
    tokay = { name = "Pixel 9"; };
    caiman = { name = "Pixel 9 Pro"; };
    komodo = { name = "Pixel 9 Pro XL"; };
    comet = { name = "Pixel 9 Pro Fold"; };
    tegu = { name = "Pixel 9a"; };
  };

  # Make a uuid based on some string data
  uuidgen = str: let
    hash = builtins.hashString "sha256" str;
    s = i: len: lib.substring i len hash;
  in lib.toLower "${s 0 8}-${s 8 4}-${s 12 4}-${s 16 4}-${s 20 12}";

  # UUID for persist.img
  uuid = uuidgen "persist-${config.buildNumber}-${builtins.toString config.buildDateTime}";
  hashSeed = uuidgen "persist-hash-${config.buildNumber}-${builtins.toString config.buildDateTime}";
in
mkMerge [
  (mkIf ((lib.elem config.flavor [ "vanilla" "grapheneos" ]) && (config.device != null) && (lib.hasAttr config.device deviceMap)) { # Default settings that apply to all devices unless overridden. TODO: Make conditional
    deviceDisplayName = mkDefault (deviceMap.${config.device}.name or config.device);
    arch = mkDefault "arm64";

    apv.img = mkDefault (fetchItem imgList);
    apv.ota = mkDefault (fetchItem otaList);

    signing.avb.enable = mkDefault true;
  })

  # Device-specific overrides
  (mkIf (builtins.elem config.device [ "marlin" "sailfish" ]) {
    signing.avb.mode = "verity_only";
    signing.apex.enable = false; # Upstream forces "TARGET_FLATTEN_APEX := false" anyway
  })
  (mkIf (lib.elem config.device [ "taimen" "muskie" ]) {
    signing.avb.mode = "vbmeta_simple";
  })
  (mkIf (builtins.elem config.device [ "crosshatch" "blueline" ]) {
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
  (mkIf (builtins.elem config.device [ "bonito" "sargo" ]) {
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
  (mkIf (lib.elem config.device [ "coral" "flame" "sunfish" "redfin" "bramble" "barbet" ]) {
    signing.avb.mode = "vbmeta_chained_v2";
  })
  (mkIf (config.device == "sunfish" && config.androidVersion >= 12) {
    signing.apex.packageNames = [ "com.android.vibrator.sunfish" ];
  })
  (mkIf (lib.elem config.deviceFamily [ "bonito" "sargo" "sunfish" "redfin" "bramble" "barbet" ] && config.androidVersion >= 12) {
    signing.apex.packageNames = [ "com.android.vibrator.drv2624" ];
  })
]
