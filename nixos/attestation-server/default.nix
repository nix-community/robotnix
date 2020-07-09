{ pkgs, callPackage, lib, substituteAll, makeWrapper, fetchFromGitHub, jdk11_headless, gradleGen,
  listenHost ? "localhost",
  port ? 8080,
  applicationId ? "org.robotnix.auditor",
  domain ? "example.org",
  signatureFingerprint ? "",
  deviceFamily ? "",
  avbFingerprint ? ""
}:
let
  buildGradle = callPackage ./gradle-env.nix {
    gradleGen = callPackage (pkgs.path + /pkgs/development/tools/build-managers/gradle) {
      java = jdk11_headless;
    };
  };
in
buildGradle {
  pname = "AttestationServer";
  version = "2020-07-01";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "AttestationServer";
    rev = "5eb5264b1ea889caca04175cb31bf6d6e83bfcc9";
    sha256 = "0bf0abma4q8jqbnsbmshfjh3ykkmqj8qfwn6lpbjf99900c6mq1h";
  };

  patches = [ (substituteAll {
    src = ./customized-attestation-server.patch;
    inherit listenHost port domain applicationId signatureFingerprint;

    taimen_avbFingerprint = if (deviceFamily == "taimen") then avbFingerprint else "DISABLED_CUSTOM_TAIMEN";
    crosshatch_avbFingerprint = if (deviceFamily == "crosshatch") then avbFingerprint else "DISABLED_CUSTOM_CROSSHATCH";
  }) ];

  JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF8";

  outputs = [ "out" "static" ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/share/java $out/bin
    mv build/libs/source.jar build/libs/AttestationServer.jar # "source" is just the name of the parent dir in the nix environment, which ought to be "AttestationServer"
    cp -r build/libs/* $out/share/java

    makeWrapper ${jdk11_headless}/bin/java $out/bin/AttestationServer \
      --add-flags "-cp $out/share/java/AttestationServer.jar:$out/share/java/* app.attestation.server.AttestationServer"

    # Static HTML output
    mkdir -p $static
    cp -r static/* $static
  '';
}
