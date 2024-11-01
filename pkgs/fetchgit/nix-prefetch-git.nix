{ lib, stdenv, makeWrapper, gnused, nix, coreutils, findutils, gawk, git, git-lfs }:

# Originally from nixpkgs/pkgs/tools/package-management/nix-prefetch-scripts
stdenv.mkDerivation {
  name = "nix-prefetch-git";

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    install -vD ${./nix-prefetch-git} $out/bin/nix-prefetch-git
    wrapProgram $out/bin/nix-prefetch-git \
      --prefix PATH : ${lib.makeBinPath [ coreutils findutils gawk git git-lfs gnused nix ]} \
      --set HOME /homeless-shelter
  '';

  preferLocalBuild = true;
}
