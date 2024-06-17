{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";

    flake-compat.url = "github:nix-community/flake-compat";

    treefmt.url = "github:numtide/treefmt";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      androidPkgs,
      flake-compat,
      treefmt,
      treefmt-nix,
      ...
    }@inputs:
    let
      pkgs = import ./pkgs/default.nix { inherit inputs; };

      treeFmt = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
      pythonForUpdaterScripts = pkgs.python3.withPackages (
        p: with p; [
          mypy
          flake8
          pytest
        ]
      );
    in
    {
      # robotnixSystem evaluates a robotnix configuration
      lib.robotnixSystem = configuration: import ./default.nix { inherit configuration pkgs; };

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
        inputsFrom = [ treeFmt.config.build.devShell ];
        nativeBuildInputs = with pkgs; [
          pythonForUpdaterScripts
          gitRepo
          nix-prefetch-git
          curl
          pup
          jq
          shellcheck
          wget

          # For chromium updater script
          # python2
          cipd
          git

          cachix
        ];
        PYTHONPATH = ./scripts;
      };

      formatter.x86_64-linux = treeFmt.config.build.wrapper;

      checks.x86_64-linux = {
        formatting = treeFmt.config.build.check self;
      };
    };
}
