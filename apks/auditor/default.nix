# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
{ callPackage, lib, substituteAll, fetchFromGitHub, androidPkgs, jdk, gradle,
  domain ? "example.org",
  applicationName ? "Robotnix Auditor",
  applicationId ? "org.robotnix.auditor",
  signatureFingerprint ? "", # Signature that this app will be signed by.
  device ? "",
  avbFingerprint ? ""
}:
let
  androidsdk = androidPkgs.sdk (p: with p; [ cmdline-tools-latest platforms-android-30 build-tools-30-0-2 ]);
  buildGradle = callPackage ./gradle-env.nix {};
  supportedDevices = import ./supported-devices.nix;
in
buildGradle rec {
  name = "Auditor-${version}.apk";
  version = "23"; # Latest as of 2020-12-08

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "Auditor";
    rev = version;
    sha256 = "116cpkqs32xgl3dp7z14lljz8grdzvys99i0gscm7hsqamjbysx2";
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

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
