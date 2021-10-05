# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ pkgs, callPackage, lib, substituteAll, makeWrapper, fetchFromGitHub, jdk16_headless, gradleGen,
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
      java = jdk16_headless;
    };
  };
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
buildGradle {
  pname = "AttestationServer";
  version = "2021-09-08";

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "AttestationServer";
    rev = "cf42a655a98c0ab890cb931077229d2234b5bf37";
    sha256 = "0riiww9gi1n5fj3d7q467cryypjwzlzrmssyh9hnqhjirgszml16";
  };

  patches = [
    (substituteAll ({
      src = ./customized-attestation-server.patch;
      inherit listenHost port domain applicationId signatureFingerprint;
    }
    // lib.genAttrs supportedDevices (d: if (device == d) then avbFingerprint else "DISABLED_CUSTOM_${d}")))
  ];

  postPatch = ''
    for f in src/main/java/app/attestation/server/*.java  static/*.{html,txt}; do
      substituteInPlace $f \
        --replace "attestation.app" "${domain}"
    done
  '';

  JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF8";

  outputs = [ "out" "static" ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/share/java $out/bin
    mv build/libs/source.jar build/libs/AttestationServer.jar # "source" is just the name of the parent dir in the nix environment, which ought to be "AttestationServer"
    cp -r build/libs/* $out/share/java

    makeWrapper ${jdk16_headless}/bin/java $out/bin/AttestationServer \
      --add-flags "-cp $out/share/java/AttestationServer.jar:$out/share/java/* app.attestation.server.AttestationServer"

    # Static HTML output
    mkdir -p $static
    cp -r static/* $static
  '';
}
