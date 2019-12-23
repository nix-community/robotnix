{ callPackage, lib, substituteAll, fetchFromGitHub, buildGradle, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-29 build-tools-29-0-2 ]);
in
buildGradle rec {
  name = "Seedvault-${version}.apk";
  version = "1.0.0-alpha1"; # Latest in development branch as of 2019-12-22

  envSpec = ./gradle-env.json;

  src = (fetchFromGitHub {
    owner = "stevesoltys";
    repo = "seedvault";
    rev = version;
    sha256 = "1dca93hcm0kpm0941daxwfimzss2imxyjpsdlf2fw8vh3x0sdb6y";
  });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
