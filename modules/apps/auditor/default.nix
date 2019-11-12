# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
# Disclaimer: I don't know what I"m doing
{ callPackage, lib, substituteAll, fetchFromGitHub, buildGradle, androidPkgs, jdk, gradle,
  domain ? "example.org",
  applicationName ? "NixDroid Auditor",
  applicationId ? "org.nixdroid.auditor",
  signatureFingerprint,
  deviceFamily ? "",
  avbFingerprint ? ""
}:
let
  androidsdk = androidPkgs.sdk (p: with p.stable; [ tools platforms.android-28 build-tools-28-0-3 ]);
in
buildGradle rec {
  name = "Auditor-${version}.apk";
  version = "16"; # Latest as of 2019-07-13

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "Auditor";
    rev = version;
    sha256 = "0krcr2sr69dzb8xjbcrwl03azpplsh2xnqmlv1rnxvbdj60ih985";
  };

  patches = [
    (substituteAll {
    src = ./customized-auditor.patch;
    inherit domain applicationName applicationId signatureFingerprint;

    taimen_avbFingerprint = if (deviceFamily == "taimen") then avbFingerprint else "DISABLED_CUSTOM_TAIMEN";
    crosshatch_avbFingerprint = if (deviceFamily == "crosshatch") then avbFingerprint else "DISABLED_CUSTOM_CROSSHATCH";
  }) ];

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
