# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
{
  callPackage,
  lib,
  stdenv,
  pkgs,
  substituteAll,
  fetchFromGitHub,
  androidPkgs,
  jdk11_headless,
  gradle,
  gradleToNixPatchedFetchers,
  domain ? "example.org",
  applicationName ? "Robotnix Auditor",
  applicationId ? "org.robotnix.auditor",
  signatureFingerprint ? "", # Signature that this app will be signed by.
  device ? "",
  avbFingerprint ? "",
}:
let
  androidsdk = androidPkgs.sdk (
    p: with p; [
      cmdline-tools-latest
      platform-tools
      platforms-android-30
      build-tools-30-0-3
    ]
  );
  buildGradle = callPackage ./gradle-env.nix { };
  supportedDevices = import ./supported-devices.nix;
in
buildGradle rec {
  name = "Auditor-${version}.apk";
  version = "29"; # Latest as of 2021-09-09

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "Auditor";
    rev = version;
    sha256 = "0hvl45m4l5x0bpqbx3iairkvsd34cf045bsqrir8111h9vh89cvc";
  };

  patches = [
    # TODO: Enable support for passing multiple device fingerprints
    (substituteAll (
      {
        src = ./customized-auditor.patch;
        inherit domain applicationName applicationId;
        signatureFingerprint = lib.toUpper signatureFingerprint;
      }
      // lib.genAttrs supportedDevices (
        d: if (device == d) then avbFingerprint else "DISABLED_CUSTOM_${d}"
      )
    ))

    # TODO: Ugly downgrades due to not being able to update to gradle 7.0.2, since its not working with gradle2nix
    ./build-hacks.patch
  ];

  # gradle2nix not working with the more recent version of com.android.tools.build:gradle for an unknown reason
  #
  # Error message: org.gradle.internal.component.AmbiguousVariantSelectionException: The consumer was configured to find an API of a component, as well as attribute 'com.android.build.api.attributes.BuildTypeAttr' with value 'debug'. However we cannot choose between the following variants of project :app:
  #   - Configuration ':app:debugApiElements' variant android-base-module-metadata declares an API of a component, as well as attribute 'com.android.build.api.attributes.BuildTypeAttr' with value 'debug':
  #       - Unmatched attributes:
  #           - Provides attribute 'artifactType' with value 'android-base-module-metadata' but the consumer didn't ask for it
  #           - Provides attribute 'com.android.build.api.attributes.VariantAttr' with value 'debug' but the consumer didn't ask for it
  postPatch = ''
    substituteInPlace build.gradle --replace "com.android.tools.build:gradle:7.0.2" "com.android.tools.build:gradle:4.0.1"
  '';

  # TODO: 2021-05-19. Now encountering another issue with gradle2nix, worked with gradle 6.7 but fails with 7.0.1
  # Had to change gradle/wrapper/gradle-wrapper.properties back to 6.7 to run gradle2nix

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk11_headless ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';

  fetchers = gradleToNixPatchedFetchers;
}
