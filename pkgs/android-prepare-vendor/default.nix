# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ stdenv, lib, callPackage, fetchurl, fetchpatch, fetchFromGitHub, autoPatchelfHook, makeWrapper,
  simg2img, zip, unzip, e2fsprogs, jq, jdk, curl, utillinux, perl, python2, python3, libarchive,
  api ? 31
}:

let
  python = if api >= 30 then python3 else python2;

  dexrepair = callPackage ./dexrepair.nix {};
  apiStr = builtins.toString api;

  version = {
    "29" = "2020-08-26";
    "30" = "2021-09-07";
    "31" = "2021-10-21";
  }.${builtins.toString api};

  src = {
    "29" = (fetchFromGitHub {
      # Android10 branch
      owner = "AOSPAlliance";
      repo = "android-prepare-vendor";
      rev = "a9602ca6ef16ff10641d668dcb203f89f402d40d";
      sha256 = "0wldj8ykwh8r7m1ff6vbkbc73a80lmmxwfmk8nm0cnzpbfk4cq7w";
    });
    "30" = (fetchFromGitHub {
      # Android11 branch
      owner = "AOSPAlliance";
      repo = "android-prepare-vendor";
      rev = "227f5ce7cd89a3f57291fe2b84869c7a5d1e17fa";
      sha256 = "07g5dcl2x44ai5q2yfq9ybx7j7kn41s82hgpv7jff5v1vr38cia9";
    });
    "31" = (fetchFromGitHub {
      owner = "grapheneos";
      repo = "android-prepare-vendor";
      rev = "7c09cb887d3b9a2643cfc6ecf3966db1e378be32";
      sha256 = "0j579ick4cihv3ha2gg0b88h33zfik118376g4rw1qfq0cwbwdg8";
    });
  }.${builtins.toString api};

in
(stdenv.mkDerivation {
  pname = "android-prepare-vendor";
  inherit src version;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    (python.withPackages (p: [ p.protobuf ])) # Python is used by "extract_android_ota_payload"
  ];

  patches = {
    "29" = [
      ./10/0001-Disable-oatdump-update.patch
      ./10/0002-Just-write-proprietary-blobs.txt-to-current-dir.patch
      ./10/0003-Allow-for-externally-set-config-file.patch
    ];
    "30" = [
      ./11/0001-Disable-oatdump-update.patch
      ./11/0002-Just-write-proprietary-blobs.txt-to-current-dir.patch
      ./11/0003-Allow-for-externally-set-config-file.patch
      ./11/0004-Add-option-to-use-externally-provided-carrier_list.p.patch
    ];
    "31" = [
      ./12/0001-Just-write-proprietary-blobs.txt-to-current-dir.patch
      ./12/0002-Allow-for-externally-set-config-file.patch
      ./12/0003-Add-option-to-use-externally-provided-carrier_list.p.patch
      ./12/0004-Add-Android-12-workaround-for-PRODUCT_COPY_FILES.patch
    ];
  }.${builtins.toString api};

  postPatch = ''
    patchShebangs ./execute-all.sh
    patchShebangs ./scripts

    for i in ./execute-all.sh ./scripts/download-nexus-image.sh ./scripts/extract-factory-images.sh ./scripts/generate-vendor.sh ./scripts/gen-prop-blobs-list.sh ./scripts/realpath.sh ./scripts/system-img-repair.sh ./scripts/extract-ota.sh; do
        sed -i '2 i export PATH=$PATH:${lib.makeBinPath [ zip unzip simg2img dexrepair e2fsprogs jq jdk utillinux perl curl libarchive ]}' $i
    done

    # Fix when using --input containing readonly files
    substituteInPlace ./scripts/generate-vendor.sh \
      --replace "cp -a " "cp -af "
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

  # To allow eval-time fetching of config resources from this repo.
  # Hack: Only known to work with fetchFromGitHub
  passthru.evalTimeSrc = builtins.fetchTarball {
    url = lib.head src.urls;
    sha256 = src.outputHash;
  };
})
