# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ stdenv, makeWrapper, buildEnv,
  coreutils, findutils, gawk, git, gnused, nix,
}:

let mkPrefetchScript = tool: src: deps:
  stdenv.mkDerivation {
    name = "nix-prefetch-${tool}";

    nativeBuildInputs = [ makeWrapper ];

    dontUnpack = true;

    installPhase = ''
      install -vD ${src} $out/bin/$name;
      wrapProgram $out/bin/$name \
        --prefix PATH : ${stdenv.lib.makeBinPath (deps ++ [ gnused nix ])} \
        --set HOME /homeless-shelter
    '';

    preferLocalBuild = true;

    meta = with stdenv.lib; {
      description = "Script used to obtain source hashes for fetch${tool}";
      maintainers = with maintainers; [ bennofs ];
      platforms = stdenv.lib.platforms.unix;
    };
  };
in 
  mkPrefetchScript "git" ./nix-prefetch-git [ coreutils findutils gawk git ]
