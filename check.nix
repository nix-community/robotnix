# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{ pkgs ? (import ./pkgs {}) }:

let
  lib = pkgs.lib;
  robotnix = configuration: import ./default.nix { inherit configuration pkgs; };
  configs = import ./configs.nix { inherit lib; };
in {
  check = lib.recurseIntoAttrs (lib.mapAttrs (name: c: (robotnix c).config.build.checkAndroid) configs);

  lineageosCheck = let
    deviceMetadata = lib.importJSON ./flavors/lineageos/device-metadata.json;
  in lib.mapAttrs (name: x: (robotnix { device=name; flavor="lineageos"; }).config.build.checkAndroid) deviceMetadata;
}
