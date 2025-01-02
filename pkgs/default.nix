# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ 
  system ? builtins.currentSystem,
  inputs ? (import ../flake/compat.nix { inherit system; }).defaultNix.inputs,
  ...
}@args:

let
  inherit (inputs) nixpkgs androidPkgs;
in nixpkgs.legacyPackages."${system}".appendOverlays [
  (self: super: {
    androidPkgs.packages = androidPkgs.packages."${system}";
    androidPkgs.sdk = androidPkgs.sdk."${system}";
  })
  (import ./overlay.nix { inherit inputs; })
]
