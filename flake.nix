{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";

    flake-compat.url = "github:nix-community/flake-compat";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      androidPkgs,
      flake-compat,
      ...
    }@inputs:
    let
      pkgs = import ./pkgs/default.nix { inherit inputs; };
      treefmtModule = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          shfmt.enable = true;
          shellcheck.enable = true;
          ruff-format.enable = true;
          # ruff-check.enable = true; TODO: fix scripts
          rustfmt.enable = true;
        };
      };
    in
    rec {
      # robotnixSystem evaluates a robotnix configuration
      lib.robotnixSystem =
        configuration:
        import ./default.nix {
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
        default = pkgs.callPackage ./develop.nix { };
        repo2nix = pkgs.mkShell {
          name = "repo2nix";
          nativeBuildInputs = with pkgs; [
            cargo
            rustc
            pkg-config
            openssl
            (callPackage ./pkgs/fetchgit/nix-prefetch-git.nix { })
          ];
        };
      };

      examples = nixpkgs.lib.genAttrs [ "lineageos" "grapheneos" ] (
        name: lib.robotnixSystem (./. + "/template/${name}.nix")
      );

      formatter.x86_64-linux = treefmtModule.config.build.wrapper;

      checks.x86_64-linux = {
        formatting = treefmtModule.config.build.check self;
      };
    };
}
