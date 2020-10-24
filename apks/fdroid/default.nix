{ callPackage, substituteAll, fetchFromGitLab, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-28 build-tools-28-0-3 ]);
  buildGradle = callPackage ./gradle-env.nix {};
in
buildGradle rec {
  name = "F-Droid-${version}.apk";
  version = "1.10";

  envSpec = ./gradle-env.json;

  src = fetchFromGitLab {
    owner = "fdroid";
    repo = "fdroidclient";
    rev = version;
    sha256 = "01kkpgzsnc2h3w0k1q44pdgqybiwsl5wwwabq0df5my6kw661c2y";
  };

  patches = [
    ./grapheneos.patch
  ];

  postPatch = ''
    substituteInPlace app/build.gradle --replace "getVersionName()" "\"${version}\""
  '';

  # Lenient dependency verification needed so we can patch aapt2. It's hash is verifid by nix anyway
  gradleFlags = [ "-Dorg.gradle.dependency.verification=lenient" "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/full/release/app-full-release-unsigned.apk $out
  '';
}
