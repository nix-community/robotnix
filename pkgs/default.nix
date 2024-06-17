# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ 
  system ? builtins.currentSystem,
  inputs ? (import ../flake/compat.nix { inherit system; }).defaultNix.inputs,
  ...
}@args:

let
  inherit (inputs) nixpkgs androidPkgs;
in nixpkgs.legacyPackages.x86_64-linux.appendOverlays [
  (self: super: {
    androidPkgs.packages = androidPkgs.packages.x86_64-linux;
    androidPkgs.sdk = androidPkgs.sdk.x86_64-linux;
  })
  (import ./overlay.nix { inherit inputs; })
]
