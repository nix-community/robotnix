{ stdenv, lib, callPackage, fetchurl, fetchpatch, fetchFromGitHub, autoPatchelfHook, makeWrapper,
  simg2img, zip, unzip, e2fsprogs, jq, jdk, curl, utillinux, perl, python2,
  api ? "29"
}:

let
  dexrepair = callPackage ./dexrepair.nix {};

  # TODO: Build this ourselves?
  oatdump = stdenv.mkDerivation {
    name = "oatdump-${api}";

    src = fetchurl {
      url = https://onedrive.live.com/download?cid=D1FAC8CC6BE2C2B0&resid=D1FAC8CC6BE2C2B0%21574&authkey=ADSQA_DtfAmmk2c;
      name = "oatdump-${api}.zip";
      sha256 = "0kiq173jqg6qzw9m5wwp0kh1d3zxxksi69xj4nwg7pp43m4lfjir";
    };

    nativeBuildInputs = [ autoPatchelfHook ];

    unpackPhase = ''
      ${unzip}/bin/unzip $src
    '';

    installPhase = ''
      mkdir -p $out
      cp -r * $out
    '';
  };
in
(stdenv.mkDerivation {
  pname = "android-prepare-vendor";
  version = "2020-05-29";

  src = fetchFromGitHub { # api == "29"
    owner = "danielfullmer";
    repo = "android-prepare-vendor";
    rev = "bfeb50a8151a3e728e5f562a2273f08e34e9ddf3";
    sha256 = "1a0f7i7y8dkzry7iyqsxjygg567c9d9ni7cc3m075x9iq2xfdkrj";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    (python2.withPackages (p: [ p.protobuf ])) # Python is used by "extract_android_ota_payload"
  ];

  patches = [ ./robotnix.patch ];

  # TODO: No need to copy oatdump now that we're making a standalone android-prepare-vendor.
  # Just patch it out instead
  postPatch = ''
    patchShebangs ./execute-all.sh
    patchShebangs ./scripts
    # TODO: Hardcoded api version
    mkdir -p hostTools/Linux/api-${api}/
    cp -r ${oatdump}/* hostTools/Linux/api-${api}/

    for i in ./execute-all.sh ./scripts/download-nexus-image.sh ./scripts/extract-factory-images.sh ./scripts/generate-vendor.sh ./scripts/gen-prop-blobs-list.sh ./scripts/realpath.sh ./scripts/system-img-repair.sh; do
        sed -i '2 i export PATH=$PATH:${stdenv.lib.makeBinPath [ zip unzip simg2img dexrepair e2fsprogs jq jdk utillinux perl curl ]}' $i
    done
  '';

  installPhase = ''
    mkdir -p $out
    cp -r * $out
  '';

  configurePhase = ":";

  postFixup = ''
    wrapProgram $out/scripts/extract_android_ota_payload/extract_android_ota_payload.py \
      --prefix PYTHONPATH : "$PYTHONPATH"
  '';
})
