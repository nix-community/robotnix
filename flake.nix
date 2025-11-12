{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";

    flake-compat.url = "github:nix-community/flake-compat";
  };

  outputs = { self, nixpkgs, androidPkgs, flake-compat,  ... }@inputs: let
    pkgs = import ./pkgs/default.nix { inherit inputs; };
  in rec {
    # robotnixSystem evaluates a robotnix configuration
    lib.robotnixSystem = configuration: import ./default.nix {
      inherit configuration pkgs;
    };

    templates.default = {
      path = ./template;
      description = "A basic robotnix configuration flake";
    };

    nixosModule = import ./nixos; # Contains all robotnix nixos modules
    nixosModules.attestation-server = import ./nixos/attestation-server/module.nix;

    packages.x86_64-linux = {
      manual = (import ./docs { inherit pkgs; }).manual;
      gitRepo = pkgs.gitRepo;
    };

    devShells.x86_64-linux = rec {
      default = pkgs.mkShell {
        name = "robotnix-scripts";
        nativeBuildInputs = with pkgs; [
          # For android updater scripts
          (python3.withPackages (p: with p; [ mypy flake8 pytest ]))
          gitRepo (callPackage ./pkgs/fetchgit/nix-prefetch-git.nix {})
          curl pup jq
          shellcheck
          wget
          signing-validator

          (callPackage ./repo2nix/package.nix {})
          prefetch-yarn-deps nodejs

          # For chromium updater script
          # python2
          # cipd git

          cachix
        ];
        PYTHONPATH=./scripts;
      };
      repo2nix = pkgs.mkShell {
        name = "repo2nix";
        nativeBuildInputs = with pkgs; [
          cargo rustc pkg-config openssl (callPackage ./pkgs/fetchgit/nix-prefetch-git.nix {})
        ];
      };
    };

    examples = nixpkgs.lib.genAttrs
      [ "lineageos" "grapheneos" ]
      (name: lib.robotnixSystem (./. + "/template/${name}.nix"));
  };
}
