with (import ./pkgs.nix);
symlinkJoin {
  name = "nixdroid-ota";
  paths = [
    #(import ./default.nix { configuration={ imports = [./marlin.nix]; }; }).otaDir
    (import ./default.nix { configuration={ imports = [./crosshatch.nix]; }; }).otaDir
  ];
}
