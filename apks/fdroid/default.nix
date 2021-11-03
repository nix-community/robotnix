# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ callPackage, stdenv, substituteAll, fetchFromGitLab,
  androidPkgs, jdk11_headless, gradle, gradleToNixPatchedFetchers
}:
let
  androidsdk = androidPkgs.sdk (p: with p; [ cmdline-tools-latest platforms-android-29 build-tools-28-0-3 ]);
  buildGradle = callPackage ./gradle-env.nix {};
in
buildGradle rec {
  name = "F-Droid-${version}.apk";
  version = "1.12.1";

  envSpec = ./gradle-env.json;

  src = fetchFromGitLab {
    owner = "fdroid";
    repo = "fdroidclient";
    rev = version;
    sha256 = "0bzsyhnii36hi8kk8s4pqj8x4scjqlhj4nh00iilq6kiqrvnc4zs";
  };

  patches = [
    ./grapheneos.patch
  ];

  postPatch = ''
    substituteInPlace app/build.gradle --replace "getVersionName()" "\"${version}\""
  '';

  # Lenient dependency verification needed so we can patch aapt2. Its hash is verified by nix anyway
  gradleFlags = [ "-Dorg.gradle.dependency.verification=lenient" "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";

  # With jdk16 in nixpkgs, gradle2nix w/ gradle 6.8.1 fails with "Unsupported class file major version 60"
  # https://github.com/gradle/gradle/issues/14273
  nativeBuildInputs = [ jdk11_headless ];

  installPhase = ''
    cp app/build/outputs/apk/full/release/app-full-release-unsigned.apk $out
  '';

  fetchers = gradleToNixPatchedFetchers;
}
