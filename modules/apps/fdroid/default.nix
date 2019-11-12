{ callPackage, substituteAll, fetchFromGitHub, buildGradle, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-27 build-tools-27-0-3 ]);
in
buildGradle rec {
  name = "F-Droid-${version}.apk";
  version = "1.6.2";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "f-droid";
    repo = "fdroidclient";
    rev = version;
    sha256 = "054qbrxl7ycn2qls41g45lc6j877w15ji4wjdm6hd2wgh9w87y9l";
  };

  patches = [
    (substituteAll { src = ./version.patch; inherit version; })
    ./grapheneos.patch
  ];

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/full/release/app-full-release-unsigned.apk $out
  '';
}
