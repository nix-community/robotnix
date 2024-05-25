# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  callPackage,
  lib,
  substituteAll,
  fetchFromGitHub,
  androidPkgs,
  jdk,
  gradle,
}:
let
  androidsdk = androidPkgs.sdk (
    p: with p; [
      cmdline-tools-latest
      platforms-android-29
      build-tools-29-0-2
    ]
  );
  buildGradle = callPackage ./gradle-env.nix { };
in
buildGradle rec {
  name = "Seedvault-${version}.apk";
  version = "2020-10-24";

  envSpec = ./gradle-env.json;

  src = (
    fetchFromGitHub {
      owner = "stevesoltys";
      repo = "seedvault";
      rev = "98e34a1eb3c85ad890d49c1199fee6d56269ba7e"; # From android10 branch
      sha256 = "059674xv1fmnsnxd5qay28pb1n6jzl6g17ykhcw7b93rpydq3r4g";
    }
  );

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
