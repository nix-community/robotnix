# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  stdenv,
  fetchurl,
  bison,
  m4,
}:

stdenv.mkDerivation {
  name = "flex-2.5.39";

  src = fetchurl {
    url = "mirror://sourceforge/flex/flex-2.5.39.tar.bz2";
    sha256 = "0zv15giw3gma03y2bzw78hjfy49vyir7vbcgnh9bb3637dgvblmd";
  };

  buildInputs = [ bison ];

  propagatedNativeBuildInputs = [ m4 ];

  meta = {
    homepage = "http://flex.sourceforge.net/";
    description = "A fast lexical analyser generator";
  };
}
