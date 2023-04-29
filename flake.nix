{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";
    androidPkgs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, androidPkgs, ... }@inputs:
    let
      pkgs = import ./pkgs/default.nix {
        inherit inputs;
      };
      python3-local = (pkgs.python39.withPackages (p: with p; [ mypy flake8 pytest ]));
    in
    rec {
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

      devShells.x86_64-linux = {
        default = pkgs.mkShell {
          name = "robotnix-scripts";
          nativeBuildInputs = with pkgs; [
            # For android updater scripts
            python3-local
            (gitRepo.override { python3 = python39; })
            nix-prefetch-git
            curl
            pup
            jq
            shellcheck
            wget

            # For chromium updater script
            python2
            cipd
            git

            cachix
          ];
          PYTHONPATH = ./scripts;
        };
      } // (pkgs.lib.mapAttrs
        (device: robotnixSystem: robotnixSystem.config.build.debugShell)
        exampleImages);
      exampleImages = (pkgs.lib.listToAttrs (map
        (device: {
          name = device;
          value = lib.robotnixSystem {
            inherit device;
            flavor = "grapheneos";
            apv.enable = false;
            adevtool.hash = "sha256-aA54o2FPfI+9iDLiUaGJAqMzUuNyWwCuWOoa1lADKuM=";
            signing = {
              enable = true;
              keyStorePath = ./test-keys;
              sopsDecrypt = {
                enable = true;
                sopsConfig = ./.sops.yaml;
                key = ./.keystore-private-keys.txt;
                keyType = "age";
              };
            };
          };
        }) [ "redfin" "bramble" "oriole" "raven" "bluejay" "panther" "cheetah" ]));
    };
}
