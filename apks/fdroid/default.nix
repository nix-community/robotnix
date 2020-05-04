{ callPackage, substituteAll, fetchFromGitLab, buildGradle, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-27 build-tools-27-0-3 ]);
in
buildGradle rec {
  name = "F-Droid-${version}.apk";
  version = "1.8";

  envSpec = ./gradle-env.json;

  src = fetchFromGitLab {
    owner = "fdroid";
    repo = "fdroidclient";
    rev = version;
    sha256 = "0xx8i7awyqbvhl2hh0kbdwp59hl9xp9bbg3mid254xnffg4yga3p";
  };

  patches = [
    ./grapheneos.patch
  ];

  postPatch = ''
    substituteInPlace app/build.gradle --replace "getVersionName()" "\"${version}\""
  '';

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/full/release/app-full-release-unsigned.apk $out
  '';
}
