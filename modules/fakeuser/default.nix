# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  stdenv,
  meson,
  ninja,
}:

stdenv.mkDerivation {
  name = "fakeuser";
  src = ./.;

  nativeBuildInputs = [
    meson
    ninja
  ];
}
