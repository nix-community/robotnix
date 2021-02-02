# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT
# Include this file in your "imports = [];"
{
  imports = [ ./attestation-server/module.nix ];

  nixpkgs.overlays = [ (self: super: {
    attestation-server = super.callPackage ./attestation-server {};
  }) ];
}
