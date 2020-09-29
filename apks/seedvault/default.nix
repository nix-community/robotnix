{ callPackage, lib, substituteAll, fetchFromGitHub, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-29 build-tools-29-0-2 ]);
  buildGradle = callPackage ./gradle-env.nix {};
in
buildGradle rec {
  name = "Seedvault-${version}.apk";
  version = "2020-09-24";

  envSpec = ./gradle-env.json;

  src = (fetchFromGitHub {
    owner = "stevesoltys";
    repo = "seedvault";
    rev = "680ad8b7db3e21cecf9dcf4d83445a8caf6b8f4d";
    sha256 = "15limcqq73xfiylcldvr25jybid8m190ypah78qgaqfdwsp6p1l9";
  });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
