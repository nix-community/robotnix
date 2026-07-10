{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";

    flake-compat.url = "github:nix-community/flake-compat";

    nixpkgs-nixfmt-old.url = "github:NixOS/nixpkgs/c7ab75210cb8cb16ddd8f290755d9558edde7ee1";
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
      lib = nixpkgs.lib;
      supportedSystems = builtins.attrNames androidPkgs.packages;
      forAllSystems = lib.genAttrs supportedSystems;
      mkPkgs = system: import ./pkgs/default.nix { inherit inputs system; };
      pkgs = mkPkgs builtins.currentSystem;
      mkTreefmtModule =
        system:
        inputs.treefmt-nix.lib.evalModule (mkPkgs system) {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt = {
              enable = true;
              package = inputs.nixpkgs-nixfmt-old.legacyPackages.${system}.nixfmt-rfc-style;
            };
            shfmt.enable = true;
            shellcheck.enable = true;
            ruff-format.enable = true;
            ruff-check.enable = true;
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

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          manual = (import ./docs { inherit pkgs; }).manual;
          gitRepo = pkgs.gitRepo;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        rec {
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
        }
      );

      examples = nixpkgs.lib.genAttrs [ "lineageos" "grapheneos" ] (
        name: lib.robotnixSystem (./. + "/template/${name}.nix")
      );

      formatter = forAllSystems (system: (mkTreefmtModule system).config.build.wrapper);

      checks = forAllSystems (system: {
        formatting = (mkTreefmtModule system).config.build.check self;
      });
    };
}
