{ callPackage, substituteAll, fetchFromGitHub, androidenv, jdk, gradle }:
with androidenv;
let
  buildGradle = callPackage ./gradle-env.nix {};

  args = {
    platformVersions = [ "27" ];
    buildToolsVersions = [ "27.0.3" ];
  };
  androidSdkFormalArgs = builtins.functionArgs composeAndroidPackages;
  androidArgs = builtins.intersectAttrs androidSdkFormalArgs args;
  androidsdk = (composeAndroidPackages androidArgs).androidsdk;
in
buildGradle rec {
  pname = "F-Droid";
  version = "1.6.2";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "f-droid";
    repo = "fdroidclient";
    rev = version;
    sha256 = "054qbrxl7ycn2qls41g45lc6j877w15ji4wjdm6hd2wgh9w87y9l";
  };

  patches = [ (substituteAll { src = ./version.patch; inherit version; }) ];

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/libexec/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    mkdir -p $out
    cp --no-preserve=all -r app/build/outputs/* $out
  '';
}
