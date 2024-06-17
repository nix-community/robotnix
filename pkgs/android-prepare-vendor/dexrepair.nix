# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  stdenv,
  fetchFromGitHub,
  zlib,
}:
stdenv.mkDerivation {
  name = "dexrepair";

  src = fetchFromGitHub {
    owner = "anestisb";
    repo = "dexrepair";
    rev = "1cac602ef0d998c658912a96aeb14274d637c6cb";
    sha256 = "1ylm7zxyl1s0l2s9sczmd2ljndfwp27jgi305lbajjhz1yl47yi5";
  };

  buildInputs = [ zlib ];

  postPatch = ''
    patchShebangs ./make.sh
  '';

  buildPhase = ''
    ./make.sh gcc
  '';

  installPhase = ''
    install -Dm755 ./bin/dexRepair $out/bin/dexrepair
  '';
}
