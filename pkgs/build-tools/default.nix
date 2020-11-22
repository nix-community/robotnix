{ lib, runCommand, androidPkgs, makeWrapper, jre8_headless }:

let
  # getName snippet originally from nixpkgs/pkgs/build-support/trivial-builders.nix
  getName = fname: apk:
    if lib.elem (builtins.typeOf apk) [ "path" "string" ]
      then lib.removeSuffix ".apk" (builtins.baseNameOf apk)
      else
        if builtins.isAttrs apk && builtins.hasAttr "name" apk
        then lib.removeSuffix ".apk" apk.name
        else throw "${fname}: please supply a `name` argument because a default name can only be computed when the `apk` is a path or is an attribute set with a `name` attribute.";

  build-tools =
    (androidPkgs.sdk (p: with p.stable; [ tools build-tools-30-0-2 ]))
    + "/share/android-sdk/build-tools/30.0.2";

  apksigner = runCommand "apksigner" { nativeBuildInputs = [ makeWrapper ]; } ''
      mkdir -p $out/bin
      makeWrapper "${jre8_headless}/bin/java" "$out/bin/apksigner" \
        --add-flags "-jar ${build-tools}/lib/apksigner.jar"
    '';

  signApk = { apk, keyPath, name ? (getName "signApk" apk) + "-signed.apk" }: runCommand name {} ''
      cp ${apk} $out
      ${apksigner}/bin/apksigner sign --key ${keyPath}.pk8 --cert ${keyPath}.x509.pem $out
    '';
in {
  inherit build-tools apksigner signApk;
}
