{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-20.09";
  };

  outputs = { self, nixpkgs, ... }: {
    # robotnixSystem evaluates a robotnix configuration
    robotnixSystem = configuration: import ./default.nix {
      inherit configuration;
      pkgs = nixpkgs.legacyPackages.x86_64-linux.appendOverlays [ (import ./pkgs/overlay.nix) ];
    };

    defaultTemplate = {
      path = ./template;
      description = "A basic robotnix configuration";
    };

    nixosModule = import ./nixos;

    checks.x86_64-linux = {};
  };
}
