# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
{ callPackage, lib, stdenv, pkgs, substituteAll, fetchFromGitHub,
  androidPkgs, jdk, gradle, gradleToNixPatchedFetchers,
  domain ? "example.org",
  applicationName ? "Robotnix Auditor",
  applicationId ? "org.robotnix.auditor",
  signatureFingerprint ? "", # Signature that this app will be signed by.
  device ? "",
  avbFingerprint ? ""
}:
let
  androidsdk = androidPkgs.sdk (p: with p; [ cmdline-tools-latest platform-tools platforms-android-30 build-tools-30-0-3 ]);
  buildGradle = callPackage ./gradle-env.nix {};
  supportedDevices = import ./supported-devices.nix;
in
buildGradle rec {
  name = "Auditor-${version}.apk";
  version = "27"; # Latest as of 2021-05-19

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "Auditor";
    rev = "e5dd999fe2bf402dd72f352b5583932e5f5d5705"; # Needs the appcompat 1.3.0 fix in a slightly newer commit
    sha256 = "1dv9yb661yl4390bawfqg0msddpyw35609y0mlxfq1psc4lssi86";
  };

  patches = [
    # TODO: Enable support for passing multiple device fingerprints
    (substituteAll ({
      src = ./customized-auditor.patch;
      inherit domain applicationName applicationId ;
      signatureFingerprint = lib.toUpper signatureFingerprint;
    }
    // lib.genAttrs supportedDevices (d: if (device == d) then avbFingerprint else "DISABLED_CUSTOM_${d}")))
  ];

  # gradle2nix not working with the more recent version of com.android.tools.build:gradle for an unknown reason
  #
  # Error message: org.gradle.internal.component.AmbiguousVariantSelectionException: The consumer was configured to find an API of a component, as well as attribute 'com.android.build.api.attributes.BuildTypeAttr' with value 'debug'. However we cannot choose between the following variants of project :app:
  #   - Configuration ':app:debugApiElements' variant android-base-module-metadata declares an API of a component, as well as attribute 'com.android.build.api.attributes.BuildTypeAttr' with value 'debug':
  #       - Unmatched attributes:
  #           - Provides attribute 'artifactType' with value 'android-base-module-metadata' but the consumer didn't ask for it
  #           - Provides attribute 'com.android.build.api.attributes.VariantAttr' with value 'debug' but the consumer didn't ask for it
  postPatch = ''
    substituteInPlace build.gradle --replace "com.android.tools.build:gradle:4.2.1" "com.android.tools.build:gradle:4.0.1"
  '';

  # TODO: 2021-05-19. Now encountering another issue with gradle2nix, worked with gradle 6.7 but fails with 7.0.1

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';

  fetchers = gradleToNixPatchedFetchers;
}
