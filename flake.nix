{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";

    flake-compat.url = "github:nix-community/flake-compat";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, androidPkgs, flake-compat,  ... }@inputs: let
    pkgs = import ./pkgs/default.nix { inherit inputs; };
  in {
    # robotnixSystem evaluates a robotnix configuration
    lib.robotnixSystem = configuration: import ./default.nix {
      inherit configuration pkgs;
    };

    defaultTemplate = {
      path = ./template;
      description = "A basic robotnix configuration";
    };

    nixosModule = import ./nixos; # Contains all robotnix nixos modules
    nixosModules.attestation-server = import ./nixos/attestation-server/module.nix;

    packages.x86_64-linux = {
      manual = (import ./docs { inherit pkgs; }).manual;
      gitRepo = pkgs.gitRepo;
    };

    devShell.x86_64-linux = pkgs.mkShell {
      name = "robotnix-scripts";
      nativeBuildInputs = with pkgs; [
        # For android updater scripts
        (python3.withPackages (p: with p; [ mypy flake8 pytest ]))
        gitRepo nix-prefetch-git
        curl pup jq
        shellcheck
        wget

        # For chromium updater script
        # python2
        cipd git

        cachix
      ];
      PYTHONPATH=./scripts;
    };
  };
}
