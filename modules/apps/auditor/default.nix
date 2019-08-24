# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
# Disclaimer: I don't know what I"m doing
{ callPackage, lib, substituteAll, fetchFromGitHub, androidenv, jdk, gradle,
  domain ? "example.org",
  applicationName ? "NixDroid Auditor",
  applicationId ? "org.nixdroid.auditor",
  signatureFingerprint,
  deviceFamily ? "",
  avbFingerprint ? ""
}:
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

  ANDROID_HOME = "${androidsdk}/libexec/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
