{ stdenv, fetchFromGitHub, zlib }:
stdenv.mkDerivation {
  name = "simg2img";

  src = fetchFromGitHub {
    owner = "anestisb";
    repo = "android-simg2img";
    rev = "223e415fb3b89c057e18c6655b034a1db60a21de"; # Latest as of 2019-04-27
    sha256 = "1cgwz7anqq531gzh86n4wg5lnh4wjxsyk3ffja8cfgj549gsyh2c";
  };

  buildInputs = [ zlib ];

  makeFlags = [ "PREFIX=$(out)" ];
}
