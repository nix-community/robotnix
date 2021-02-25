# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ overlays ? [ ], ... }@args:

let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);

  nixpkgs = fetchTarball (with lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked; {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    sha256 = narHash;
  });

  androidPkgs = fetchTarball (with lock.nodes.${lock.nodes.root.inputs.androidPkgs}.locked; {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    sha256 = narHash;
  });

in
import nixpkgs ({
  overlays = overlays ++ [
    (self: super: {
      androidPkgs = import androidPkgs { pkgs = self; };
    })
    (import ./overlay.nix)
  ];
} // builtins.removeAttrs args [ "overlays" ])
