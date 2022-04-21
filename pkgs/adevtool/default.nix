{ lib, yarn2nix-moretea, nodejs-17_x, fetchFromGitHub }:

let
  # Needs nodejs>=17 for structuredConfig function
  yarn2nix = yarn2nix-moretea.override { nodejs = nodejs-17_x; };

  inherit (yarn2nix)
  mkYarnPackage;

  src = fetchFromGitHub {
    owner = "kdrag0n";
    repo = "adevtool";
    rev = "12c5b4ea4b38e7bf97c0d9a1c2e40534f01a60cf";
    sha256 = "17sshf55frnxkk8ag27pgf7yzvgrdpzilfnsmzskxp4mz7f3izz9";
  };

in mkYarnPackage {
  pname = "adevtool";
  inherit src;

  # To allow eval-time fetching of config resources from this repo.
  # Hack: Only known to work with fetchFromGitHub
  passthru.evalTimeSrc = builtins.fetchTarball {
    url = lib.head src.urls;
    sha256 = src.outputHash;
  };
}
