# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
# Disclaimer: I don't know what I"m doing
{ callPackage, lib, substituteAll, fetchFromGitHub, androidenv, jdk, gradle,
  domain ? "",
  platformFingerprint ? "",
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
  version = "15"; # Latest as of 2019-07-13

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "Auditor";
    rev = version;
    sha256 = "1bphv3d2rlflwhffp2lw83dp22sx640nj93gk5cfzirkkf5pc1kd";
  };

  patches = [
    ./0001-Downgrade-build-tools-temporarily.patch # 29.0.0 not yet in nixpkgs
  ] ++ lib.optional (domain != "") (substituteAll { src = ./0002-Custom-domain.patch; inherit domain; })
    ++ lib.optional (platformFingerprint != "") (substituteAll {
      src = ./0003-Custom-fingerprints.patch;
      inherit platformFingerprint;
      # TODO: Allow passing in a bunch of fingerprints so multiple custom devices can cross validate each other
      taimen_avbFingerprint = if (deviceFamily == "taimen") then avbFingerprint else "DISABLED_CUSTOM_TAIMEN";
      crosshatch_avbFingerprint = if (deviceFamily == "crosshatch") then avbFingerprint else "DISABLED_CUSTOM_CROSSHATCH";
    });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/libexec/android-sdk";
  nativeBuildInputs = [ jdk gradle ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
