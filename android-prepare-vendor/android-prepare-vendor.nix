{ stdenv, lib, callPackage, fetchurl, fetchFromGitHub, autoPatchelfHook, makeWrapper,
  simg2img, zip, unzip, e2fsprogs, jq, jdk, wget, utillinux, perl, which,
  api ? "28"
}:

let
  buildID = "nixdroid"; # Doesn't have to match the real buildID
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
  version = "2019-07-13";

  # TODO: Unify these
  src = if (api == "28") then (fetchFromGitHub {
    owner = "anestisb";
    repo = "android-prepare-vendor";
    rev = "e853d17c89f6962d3fd6f408db8576e6b445f643";
    sha256 = "1aicx4lh1gvrbq4llh0dqifhp3y5d4g44r271b2qbg3vpkz48alb";
  }) else (fetchFromGitHub { # api == "29"
    owner = "RattlesnakeOS";
    repo = "android-prepare-vendor";
    rev = "6f8cf1be159e67ef39242fbcae2458fa7251f6bd";
    sha256 = "1ap7lghbrif49171hna23jim4jx2qbvnizgpi1dfhqf5bb79s8i0";
  });

  nativeBuildInputs = [ makeWrapper ];

  patches = [ ./android-prepare-vendor.patch ];

  postPatch = ''
    patchShebangs ./execute-all.sh
    patchShebangs ./scripts
    # TODO: Hardcoded api version
    mkdir -p hostTools/Linux/api-${api}/
    cp -r ${oatdump}/* hostTools/Linux/api-${api}/

    for i in ./execute-all.sh ./scripts/download-nexus-image.sh ./scripts/extract-factory-images.sh ./scripts/generate-vendor.sh ./scripts/gen-prop-blobs-list.sh ./scripts/realpath.sh ./scripts/system-img-repair.sh; do
        sed -i '2 i export PATH=$PATH:${stdenv.lib.makeBinPath [ zip unzip simg2img dexrepair e2fsprogs jq jdk wget utillinux perl which ]}' $i
    done
  '';

  installPhase = ''
    mkdir -p $out
    cp -r * $out
  '';

  configurePhase = ":";
  fixupPhase = ":";
})
