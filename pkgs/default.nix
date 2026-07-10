# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  system ? builtins.currentSystem,
  inputs ? (import ../flake/compat.nix { inherit system; }).defaultNix.inputs,
  ...
}@args:

let
  inherit (inputs) nixpkgs androidPkgs;
  supportedSystems = nixpkgs.lib.intersectLists (builtins.attrNames androidPkgs.packages) (
    builtins.attrNames androidPkgs.sdk
  );
in
if !(builtins.elem system supportedSystems) then
  throw "robotnix does not support host system `${system}`. Supported systems: ${builtins.concatStringsSep ", " supportedSystems}"
else
  nixpkgs.legacyPackages.${system}.appendOverlays [
    (self: super: {
      androidPkgs.packages = androidPkgs.packages.${system};
      androidPkgs.sdk = androidPkgs.sdk.${system};
    })
    (import ./overlay.nix { inherit inputs; })
  ]
