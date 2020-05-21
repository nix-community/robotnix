{ stdenv, lib, callPackage, fetchurl, fetchpatch, fetchFromGitHub, autoPatchelfHook, makeWrapper,
  simg2img, zip, unzip, e2fsprogs, jq, jdk, curl, utillinux, perl, python2,
  api ? "29"
}:

let
  dexrepair = callPackage ./dexrepair.nix {};

  # TODO: This is for API-28. Need to make this work for all of them. Preferably without downloading each one
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
  # TODO: Make sure it can use java if it doesn't use oatdump.
in
(stdenv.mkDerivation {
  pname = "android-prepare-vendor";
  version = "2020-05-21";

  src = fetchFromGitHub { # api == "29"
    owner = "danielfullmer";
    repo = "android-prepare-vendor";
    rev = "84f0d7dee8ab25eea7e8c023369112b5e10f657b";
    sha256 = "1bhxy76gibax8sxfcs1bxc116261wf22p5r8apvq7l7qzrib1g02";
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
