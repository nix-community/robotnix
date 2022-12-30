# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ inputs ? (import (
    fetchTarball {
      url = "https://github.com/edolstra/flake-compat/archive/12c64ca55c1014cdc1b16ed5a804aa8576601ff2.tar.gz";
      sha256 = "0jm6nzb83wa6ai17ly9fzpqc40wg1viib8klq8lby54agpl213w5"; }
  ) {
    src =  ../.;
  }).defaultNix.inputs,
  system,
  ... }@args:

let
  inherit (inputs) nixpkgs nixpkgsUnstable androidPkgs;
in nixpkgs.legacyPackages."${system}".appendOverlays [
  (self: super: {
    androidPkgs.packages = androidPkgs.packages."${system}";
    androidPkgs.sdk = androidPkgs.sdk."${system}";

    inherit (nixpkgsUnstable.legacyPackages."${system}")
      diffoscope;
  })
  (import ./overlay.nix)
]
