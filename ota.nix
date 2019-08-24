with (import ./pkgs.nix);
symlinkJoin {
  name = "nixdroid-ota";
  paths = [
    (import ./default.nix { configuration=./marlin.nix; }).config.build.otaDir
    (import ./default.nix { configuration=./crosshatch.nix; }).config.build.otaDir
  ];
}
