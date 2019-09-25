with (import ./pkgs.nix);
symlinkJoin {
  name = "nixdroid-ota";
  paths = [
    (import ./default.nix { configuration=./marlin.nix; }).otaDir
    (import ./default.nix { configuration=./crosshatch.nix; }).otaDir
  ];
}
