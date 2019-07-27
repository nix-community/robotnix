with (import <nixpkgs> {});
symlinkJoin {
  name = "nixdroid-ota";
  paths = [
    (import ./default.nix { configuration=(import ./marlin.nix); }).config.build.otaDir
    (import ./default.nix { configuration=(import ./crosshatch.nix); }).config.build.otaDir
  ];
}
