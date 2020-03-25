{ lib, runCommand, callPackage, cacert, cipd }:

{ name ? builtins.baseNameOf package
, package
, version
, sha256
}:

runCommand name {
  nativeBuildInputs = [ cipd cacert ];

  outputHashAlgo = "sha256";
  outputHashMode = "recursive";
  outputHash = sha256;

  preferLocalBuild = true;
} ''
  mkdir -p $out
  cd $out
  cipd init
  cipd install -- "${package}" "${version}"
''
# TODO: Remove symlinks and .cipd dirs?
