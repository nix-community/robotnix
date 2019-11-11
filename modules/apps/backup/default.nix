{ callPackage, lib, substituteAll, fetchFromGitHub, androidPkgs, jdk, gradle, }:
let
  buildGradle = callPackage ./gradle-env.nix {}; # Needs a modified version to patch aapt2 binary in a jar
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-28 build-tools-28-0-3 ]);
in
buildGradle rec {
  name = "Backup-${version}.apk";
  version = "16-pre"; # Latest in development branch as of 2019-07-31

  envSpec = ./gradle-env.json;

  src = (fetchFromGitHub {
    owner = "stevesoltys";
    repo = "backup";
    rev = "6136f589c16cef3595a4f263b42cf1e398d05ba2";
    sha256 = "1ldlhw104vb9fkwpfh3pk1vh7w2c64sxgjvdgawnjjr14pclpx2d";
  });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
