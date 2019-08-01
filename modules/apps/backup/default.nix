{ callPackage, lib, substituteAll, fetchFromGitHub, androidenv, jdk, gradle, }:
with androidenv;
let
  buildGradle = callPackage ./gradle-env.nix {}; # Needs a modified version to patch aapt2 binary in a jar

  args = {
    platformVersions = [ "28" ];
  };
  androidSdkFormalArgs = builtins.functionArgs composeAndroidPackages;
  androidArgs = builtins.intersectAttrs androidSdkFormalArgs args;
  androidsdk = (composeAndroidPackages androidArgs).androidsdk;
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

  ANDROID_HOME = "${androidsdk}/libexec/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
