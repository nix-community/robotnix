# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ pkgs, callPackage, lib, substituteAll, makeWrapper, fetchFromGitHub, jdk11_headless, gradleGen,
  listenHost ? "localhost",
  port ? 8080,
  applicationId ? "org.robotnix.auditor",
  domain ? "example.org",
  signatureFingerprint ? "",
  device ? "",
  avbFingerprint ? ""
}:
let
  buildGradle = callPackage ./gradle-env.nix {
    gradleGen = callPackage (pkgs.path + /pkgs/development/tools/build-managers/gradle) {
      java = jdk11_headless;
    };
  };
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
buildGradle {
  pname = "AttestationServer";
  version = "2021-03-19";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "AttestationServer";
    rev = "c32a02f2248e33f24408bcbe91d377398fbb4ca5";
    sha256 = "1k7awwf8j6hb5w3wxy5yl4maj2siwi4863nhv84flhhzw6xvpkkn";
  };

  patches = [
    (substituteAll ({
      src = ./customized-attestation-server.patch;
      inherit listenHost port domain applicationId signatureFingerprint;
    }
    // lib.genAttrs supportedDevices (d: if (device == d) then avbFingerprint else "DISABLED_CUSTOM_${d}")))
  ];

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
