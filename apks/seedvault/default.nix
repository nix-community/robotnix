{ callPackage, lib, substituteAll, fetchFromGitHub, buildGradle, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-29 build-tools-29-0-2 ]);
in
buildGradle rec {
  name = "Seedvault-${version}.apk";
  version = "1.0.0";

  envSpec = ./gradle-env.json;

  src = (fetchFromGitHub {
    owner = "stevesoltys";
    repo = "seedvault";
    rev = version;
    sha256 = "0pzx7gbn3lldi8gzdf5ww1yljs54yicv0i5dxnlvmpiy249cag2m";
  });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
