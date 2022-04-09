{ pkgs ? (import ./pkgs {}) }:

let
  lib = pkgs.lib;

  filterForDerivations = lib.mapAttrs (name: value:
    if lib.isDerivation value then value
    else if value.recurseForDerivations or false then filterForDerivations value
    else {}
  );
in
  filterForDerivations (import ./release.nix { inherit pkgs; })
