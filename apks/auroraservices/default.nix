# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ callPackage
, stdenv
, substituteAll
, fetchFromGitLab
, androidPkgs
, jdk11_headless
, gradle
, gradleToNixPatchedFetchers
}:
let
  androidsdk = androidPkgs.sdk (p: with p; [ cmdline-tools-latest platforms-android-29 build-tools-28-0-3 ]);
  buildGradle = callPackage ./gradle-env.nix { };
in
buildGradle rec {
  name = "AuroraServices_v${version}.apk";
  version = "1.1.1";
  #https://gitlab.com/AuroraOSS/AuroraServices/uploads/c22e95975571e9db143567690777a56e/

  envSpec = ./gradle-env.json;

  src = fetchFromGitLab {
    owner = "AuroraOSS";
    repo = "AuroraServices";
    rev = "1.1.1";
    sha256 = "cYaviNIcZ03tsqLZwxSb85r04KAG6rirDL8xWFLo2ms=";
  };

  postPatch = ''
    substituteInPlace app/build.gradle --replace "getVersionName()" "\"${version}\""
  '';

  # Lenient dependency verification needed so we can patch aapt2. Its hash is verifid by nix anyway
  gradleFlags = [ "-Dorg.gradle.dependency.verification=lenient" "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";

  # With jdk16 in nixpkgs, gradle2nix w/ gradle 6.8.1 fails with "Unsupported class file major version 60"
  # https://github.com/gradle/gradle/issues/14273
  nativeBuildInputs = [ jdk11_headless ];

  installPhase = ''
    cp app/build/outputs/apk/full/release/app-full-release-unsigned.apk $out
  '';

  #fetchers = gradleToNixPatchedFetchers;
}
