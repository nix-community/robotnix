# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  callPackage,
  runCommand,
  androidPkgs,
  makeWrapper,
  jre8_headless,
  openssl,
}:

let
  unpack-images = callPackage ./unpack-images.nix { };

  # Try to avoid using the derivations below, since they rely on "import-from-derivation"
  apkFingerprint =
    apk:
    (import runCommand "apk-fingerprint" { nativeBuildInputs = [ jre8_headless ]; } ''
      fingerprint=$(keytool -printcert -jarfile ${apk} | grep "SHA256:" | tr --delete ':' | cut --delimiter ' ' --fields 3)
      echo "\"$fingerprint\"" > $out
    '');

  certFingerprint =
    cert:
    (import (
      runCommand "cert-fingerprint" { } ''
        ${openssl}/bin/openssl x509 -noout -fingerprint -sha256 -in ${cert} | awk -F"=" '{print "\"" $2 "\"" }' | sed 's/://g' > $out
      ''
    ));

  sha256Fingerprint = file: lib.toUpper (builtins.hashFile "sha256" file);

  # getName snippet originally from nixpkgs/pkgs/build-support/trivial-builders.nix
  getName =
    fname: apk:
    if
      lib.elem (builtins.typeOf apk) [
        "path"
        "string"
      ]
    then
      lib.removeSuffix ".apk" (builtins.baseNameOf apk)
    else if builtins.isAttrs apk && builtins.hasAttr "name" apk then
      lib.removeSuffix ".apk" apk.name
    else
      throw "${fname}: please supply a `name` argument because a default name can only be computed when the `apk` is a path or is an attribute set with a `name` attribute.";

  build-tools =
    (androidPkgs.sdk (
      p: with p; [
        cmdline-tools-latest
        build-tools-31-0-0
      ]
    ))
    + "/share/android-sdk/build-tools/31.0.0";

  apksigner = runCommand "apksigner" { nativeBuildInputs = [ makeWrapper ]; } ''
    mkdir -p $out/bin
    makeWrapper "${jre8_headless}/bin/java" "$out/bin/apksigner" \
      --add-flags "-jar ${build-tools}/lib/apksigner.jar"
  '';

  signApk =
    {
      apk,
      keyPath,
      name ? (getName "signApk" apk) + "-signed.apk",
    }:
    runCommand name { } ''
      cp ${apk} $out
      ${apksigner}/bin/apksigner sign --key ${keyPath}.pk8 --cert ${keyPath}.x509.pem $out
    '';

  # Currently only supports 1 signer.
  verifyApk =
    {
      apk,
      sha256,
      name ? (getName "verifyApk" apk) + ".apk",
    }:
    runCommand name { } ''
      sha256=$(${apksigner}/bin/apksigner verify --print-certs ${apk} | grep "^Signer #1 certificate SHA-256 digest: " | cut -d" " -f6 || exit 1)

      if [[ "$sha256" = "${sha256}" ]]; then
        echo "${name} APK certificate digest matches ${sha256}"
        ln -s ${apk} $out
      else
        echo "${name} APK certificate digest $sha256 is not ${sha256}"
        exit 1
      fi
    '';

  # Unpack and compare two images
  # Excludes known differences--also all of the APKs since signatures are different. TODO: Copy/replace sigs
  compareImagesQuickDiff =
    a: b:
    pkgs.runCommand "images.diff" { } ''
      ln -s ${pkgs.robotnix.unpackImg a} a
      ln -s ${pkgs.robotnix.unpackImg b} b

      cat >excludes <<EOF
      *.apk
      plat_mac_permissions.xml
      vendor_mac_permissions.xml
      file_signatures.txt
      otacerts.zip
      EOF

      diff -ur --exclude-from=excludes a b > $out || true
    '';

  compareImagesDiffoscope =
    a: b:
    pkgs.runCommand "images-diffoscope"
      {
        nativeBuildInputs = with pkgs; [
          diffoscope
          pkgsCross.aarch64-multiplatform.buildPackages.binutils-unwrapped
        ];
      }
      ''
        mkdir -p $out
        diffoscope \
          --html-dir $out \
          --tool-prefix-binutils aarch64-unknown-linux-gnu- \
          --exclude "**/META-INF/CERT.RSA" \
          --exclude-command "^xxd" \
          ${a} ${b} || true
      '';
in
{
  inherit
    build-tools
    apksigner
    signApk
    verifyApk
    apkFingerprint
    certFingerprint
    sha256Fingerprint
    compareImagesQuickDiff
    compareImagesDiffoscope
    ;

  inherit (unpack-images) unpackImg unpack_bootimg avbtool;
}
