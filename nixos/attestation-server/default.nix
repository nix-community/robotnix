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
  version = "2020-10-04";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "AttestationServer";
    rev = "da766d6366b2335e5e8713f19140210e1bafd75d";
    sha256 = "0mhlllriim244f0kggbrvg7zpyqxc4c7lj2z34nc0n4dj8yw4xgj";
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
