{ callPackage, lib, substituteAll, fetchFromGitHub, buildGradle, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-29 build-tools-29-0-2 ]);
in
buildGradle rec {
  name = "Seedvault-${version}.apk";
  version = "1.0.0-alpha1"; # Latest in development branch as of 2019-11-11

  envSpec = ./gradle-env.json;

  src = (fetchFromGitHub {
    owner = "stevesoltys";
    repo = "seedvault";
    rev = "8686ee6c903b0d22bbd616733dd3dcdb62a9c2a8";
    sha256 = "0i1nfqfq7g3qs11j9xmrks7jb8asdpa96pa6k0djrvf2p8jcc26m";
  });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
