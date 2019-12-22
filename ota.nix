with (import ./pkgs.nix {});
symlinkJoin {
  name = "nixdroid-ota";
  paths = [
    (import ./default.nix { configuration={
      imports = [./example.nix];
      device = "marlin";
      flavor = "vanilla";
    }; }).otaDir
    (import ./default.nix { configuration={
      imports = [./example.nix];
      device = "crosshatch";
      flavor = "grapheneos";
    }; }).otaDir
  ];
}
