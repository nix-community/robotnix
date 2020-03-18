# Include this file in your "imports = [];"
{
  imports = [ ./attestation-server/module.nix ];

  nixpkgs.overlays = [ (self: super: {
    attestation-server = super.callPackage ./attestation-server {};
  }) ];
}
