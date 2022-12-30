{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, androidPkgs, ... }@inputs: let
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
    };

    devShell.x86_64-linux = pkgs.mkShell {
      name = "robotnix-scripts";
      nativeBuildInputs = with pkgs; [
        # For android updater scripts
        (python39.withPackages (p: with p; [ mypy flake8 pytest ]))
        (gitRepo.override { python3 = python39; }) nix-prefetch-git
        curl pup jq
        shellcheck
        wget

        # For chromium updater script
        python2 cipd git

        cachix
      ];
      PYTHONPATH=./scripts;
    };
  };
}
