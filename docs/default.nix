{ pkgs ? import ../pkgs {} }:

let
  eval = import ../default.nix { inherit pkgs; configuration = {}; };

  robotnixOptionsDoc = pkgs.nixosOptionsDoc {
    options = eval.options;
  };
in
  pkgs.runCommandNoCC "robotnix-options-docs" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    mkdir -p $out
    python3 ${./gen-options-md.py} ${robotnixOptionsDoc.optionsJSON}/share/doc/nixos/options.json > $out/options.md
  ''
