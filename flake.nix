{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-20.09";
    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";
  };

  outputs = { self, nixpkgs, androidPkgs, ... }: {
    # robotnixSystem evaluates a robotnix configuration
    lib.robotnixSystem = configuration: import ./default.nix {
      inherit configuration;
      pkgs = nixpkgs.legacyPackages.x86_64-linux.appendOverlays [
        (self: super: {
          androidPkgs.sdk = androidPkgs.sdk.x86_64-linux;
        })
        (import ./pkgs/overlay.nix)
      ];
    };

    defaultTemplate = {
      path = ./template;
      description = "A basic robotnix configuration";
    };

    nixosModule = import ./nixos; # Contains all robotnix nixos modules
    nixosModules.attestation-server = import ./nixos/attestation-server/module.nix;

    checks.x86_64-linux = {};
  };
}
