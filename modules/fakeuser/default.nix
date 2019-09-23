{ stdenv, meson, ninja }:

stdenv.mkDerivation {
  name = "fakeuser";
  src = ./.;

  nativeBuildInputs = [ meson ninja ];
}
