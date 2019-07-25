{ stdenv, lib, callPackage, fetchurl, fetchFromGitHub, autoPatchelfHook, zip, unzip, e2fsprogs, jq, openjdk, wget, utillinux, perl, which,
  device, img, full ? false
}:

let
  buildID = "nixdroid"; # Doesn't have to match the real buildID
  simg2img = callPackage ./simg2img.nix {};
  dexrepair = callPackage ./dexrepair.nix {};

  # TODO: This is for API-28. Need to make this work for all of them. Preferably without downloading each one
  api = "28";
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
  pname = "android-prepare-vendor-${device}";
  version = "2019-07-13";

  src = fetchFromGitHub {
    owner = "anestisb";
    repo = "android-prepare-vendor";
    rev = "e853d17c89f6962d3fd6f408db8576e6b445f643";
    sha256 = "1aicx4lh1gvrbq4llh0dqifhp3y5d4g44r271b2qbg3vpkz48alb";
  };

  nativeBuildInputs = [ zip unzip simg2img dexrepair e2fsprogs jq openjdk wget utillinux perl which ];

  prePatch = ''
    patchShebangs ./execute-all.sh
    patchShebangs ./scripts
    # TODO: Hardcoded api version
    mkdir -p hostTools/Linux/api-${api}/
    cp -r ${oatdump}/* hostTools/Linux/api-${api}/

    # Disable oatdump update check
    substituteInPlace execute-all.sh --replace "needs_oatdump_update() {" "needs_oatdump_update() { return 1"
  '';

  patches = [ ./reproducibility.patch ];

  # Set timestamp for reproducibility
  buildPhase = ''
    mkdir -p tmp
    ./execute-all.sh ${lib.optionalString full "--full"} --yes --output tmp --device "${device}" --buildID "${buildID}" -i "${img}" --debugfs --timestamp 1
  '';

  installPhase = ''
    mkdir -p $out
    cp -r tmp/*/*/{vendor,vendor_overlay} $out/
  '';

  configurePhase = ":";
  fixupPhase = ":";
})
