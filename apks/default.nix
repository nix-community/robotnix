# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ pkgs ? (import ../pkgs { }) }:

let
  inherit (pkgs) callPackage lib stdenv;

  gradleToNixPatchedFetchers =
    let
      patchJar = jar: stdenv.mkDerivation {
        name = "patched.jar";
        src = jar;

        phases = "unpackPhase buildPhase installPhase";

        nativeBuildInputs = with pkgs; [ unzip zip autoPatchelfHook ];

        unpackPhase = "unzip $src";
        buildPhase = "autoPatchelf .";
        installPhase = "zip -r $out *";
      };

      fetchurl' = args:
        if (lib.hasSuffix "-linux.jar" (lib.head args.urls))
        then patchJar (pkgs.fetchurl args)
        else pkgs.fetchurl args;
    in
    {
      http = fetchurl';
      https = fetchurl';
    };
in
rec {
  auditor = callPackage ./auditor { inherit gradleToNixPatchedFetchers; };

  fdroid = callPackage ./fdroid { inherit gradleToNixPatchedFetchers; };

  seedvault_10 = callPackage ./seedvault_10 { }; # Old version that works with Android 10

  # Chromium-based browsers
  chromium =
    callPackage ./chromium/default.nix {
      pkgsBuildHost = pkgs;
    };
  vanadium = import ./chromium/vanadium.nix {
    inherit chromium;
    inherit (pkgs) fetchFromGitHub git fetchcipd linkFarmFromDrvs fetchurl lib;
  };
  bromite = import ./chromium/bromite.nix {
    inherit chromium;
    inherit (pkgs) fetchFromGitHub git python3;
  };
}
