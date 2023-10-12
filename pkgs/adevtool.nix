{ yarn2nix-moretea, nodejs, p7zip, python3 }:

src:
let
  python3WP = python3.withPackages (ps: with ps; [ protobuf ]);
in
yarn2nix-moretea.mkYarnPackage {
  inherit src;
  name = "adevtool";
  buildInputs = [ nodejs ];
  nativeBuildInputs = [ python3WP ];
  yarnFlags = [
    "--offline"
    "--frozen-lockfile"
    "--ignore-engines"
    "--ignore-scripts"
    "--verbose"
  ];
  patchPhase = ''
    set -e
    sed -i 's|mount -o ro \(\''${imgPath}\) \(\''${mountpoint}\)|${p7zip}/bin/7z x -o\2 \1|' ./src/util/fs.ts
    sed -i 's|umount|rm -rf|' ./src/util/fs.ts
    patchShebangs external/
  '';
}
