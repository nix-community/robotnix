{ pkgs ? (import ./pkgs {}) }:
pkgs.mkShell {
  name = "robotnix-scripts";
  nativeBuildInputs = with pkgs; [
    # For android updater scripts
    (python3.withPackages (p: with p; [ mypy flake8 pytest ]))
    gitRepo nix-prefetch-git
    curl go-pup jq

    # For chromium updater script
    python2 cipd git

    cachix
  ];
  PYTHONPATH=".";
}
