# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  pkgs,
  callPackage,
  lib,
  substituteAll,
  makeWrapper,
  fetchFromGitHub,
  jdk17_headless,
  gradleGen,
  listenHost ? "localhost",
  port ? 8080,
  applicationId ? "org.robotnix.auditor",
  domain ? "example.org",
  signatureFingerprint ? "",
  device ? "",
  avbFingerprint ? "",
}:
let
  jdk = jdk17_headless;
  buildGradle = callPackage ./gradle-env.nix {
    gradleGen = callPackage (pkgs.path + /pkgs/development/tools/build-managers/gradle) { java = jdk; };
  };
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
buildGradle {
  pname = "AttestationServer";
  version = "2021-10-13";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "AttestationServer";
    rev = "47be83795d2f9836fe40bd0f1914abab8bb9d043";
    sha256 = "10kz6lb0s7vhq253vl538hin4k6pz0g80wg5xqd35fih0p9a966p";
  };

  patches = [
    (substituteAll (
      {
        src = ./customized-attestation-server.patch;
        inherit
          listenHost
          port
          domain
          applicationId
          signatureFingerprint
          ;
      }
      // lib.genAttrs supportedDevices (
        d: if (device == d) then avbFingerprint else "DISABLED_CUSTOM_${d}"
      )
    ))
  ];

  postPatch = ''
    for f in src/main/java/app/attestation/server/*.java  static/*.{html,txt}; do
      substituteInPlace $f \
        --replace "attestation.app" "${domain}"
    done
  '';

  JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF8";

  outputs = [
    "out"
    "static"
  ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/share/java $out/bin
    mv build/libs/source.jar build/libs/AttestationServer.jar # "source" is just the name of the parent dir in the nix environment, which ought to be "AttestationServer"
    cp -r build/libs/* $out/share/java

    makeWrapper ${jdk}/bin/java $out/bin/AttestationServer \
      --add-flags "-cp $out/share/java/AttestationServer.jar:$out/share/java/* app.attestation.server.AttestationServer"

    # Static HTML output
    mkdir -p $static
    cp -r static/* $static
  '';
}
