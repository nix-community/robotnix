{
  stdenv,
  fetchgit,
  runCommand,
  python3,
  libarchive,
  file,
  e2fsprogs,
  simg2img,
  lz4,
  cpio,
}:
let
  unpack_bootimg = stdenv.mkDerivation {
    pname = "unpack-bootimg";
    version = "2021-09-10";

    src = fetchgit {
      url = "https://android.googlesource.com/platform/system/tools/mkbootimg";
      rev = "d0d261f3b0f57105f570a9878e748d817a3c5e60";
      sha256 = "1agwi6aripi1mwv9cx38q5944g7nw3kccfwa2y73n3v22vrnlw4r";
    };

    buildInputs = [ python3 ];

    installPhase = ''
      mkdir -p $out/bin
      cp *.py $out/bin
    '';
  };

  avbtool = stdenv.mkDerivation {
    pname = "avbtool";
    version = "2021-09-10";

    src = fetchgit {
      url = "https://android.googlesource.com/platform/external/avb";
      rev = "f3549e64a153896f4d45367d0f7752005d8f6ed9";
      sha256 = "0d6dw11yb4r05va2472myd0b0b27fv4n7cj27w2w73qsrlg6100z";
    };

    buildInputs = [ python3 ];

    installPhase = ''
      mkdir -p $out/bin
      cp *.py $out/bin
    '';
  };

  unpackImg =
    img:
    runCommand "unpacked-img"
      {
        nativeBuildInputs = [
          libarchive
          file
          e2fsprogs
          simg2img
          lz4
          cpio
          unpack_bootimg
          avbtool
        ];
      }
      ''
        mkdir -p $out
        bash ${./unpack-images.sh} ${img} $out
      '';
in
{
  inherit unpackImg;

  inherit unpack_bootimg avbtool;
}
