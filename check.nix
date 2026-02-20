# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{
  pkgs ? (import ./pkgs { }),
}:

let
  lib = pkgs.lib;
  robotnix = configuration: import ./default.nix { inherit configuration pkgs; };
  configs = import ./configs.nix { inherit lib; };

  # TODO: Reunify with module in reproducibility reports
  snakeoilSignedModule =
    { config, ... }:
    let
      snakeoilKeys = pkgs.runCommand "snakeoil-keys" { } ''
        mkdir -p $out
        ${config.build.generateKeysScript} $out
      '';
    in
    {
      signing.enable = true;
      signing.keyStorePath = builtins.toString snakeoilKeys;
      signing.buildTimeKeyStorePath = "${snakeoilKeys}";
    };
in
{
  check = lib.recurseIntoAttrs (
    lib.mapAttrs (name: c: (robotnix c).config.build.checkAndroid) configs
  );

  lineageosCheck =
    let
      deviceMetadata = lib.importJSON ./flavors/lineageos/device-metadata.json;
    in
    lib.mapAttrs (
      name: x:
      (robotnix {
        device = name;
        flavor = "lineageos";
      }).config.build.checkAndroid
    ) deviceMetadata;

  # Generates img and ota files for each configuration using snakeoil keys
  # Uses IFD
  signingCheck =
    lib.mapAttrs
      (name: c: {
        inherit
          (robotnix {
            imports = [
              snakeoilSignedModule
              c
            ];
          })
          img
          ota
          ;
      })
      {
        "lineageos-10" = {
          device = "marlin";
          flavor = "lineageos";
          androidVersion = 10;
        };
        "vanilla-10" = {
          device = "sunfish";
          flavor = "vanilla";
          androidVersion = 10;
          apv.enable = false;
        }; # APV not working on Android 10...
        "vanilla-11" = {
          device = "sunfish";
          flavor = "vanilla";
          androidVersion = 11;
        };
        "vanilla-12" = {
          device = "sunfish";
          flavor = "vanilla";
          androidVersion = 12;
        };
      };
}
