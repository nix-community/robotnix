{ configuration,
  pkgs ? import ./pkgs.nix,
  lib ? pkgs.stdenv.lib
}:

let
  nixdroidlib = import ./lib lib;
in
lib.evalModules {
  modules = [
    { _module.args.pkgs = pkgs;
      _module.args.lib = lib;
      _module.args.nixdroidlib = nixdroidlib;
    }
    configuration 
    ./flavors/grapheneos.nix
    ./flavors/vanilla.nix
    ./flavors/common.nix
    ./flavors/pixel.nix
    ./modules/apps/auditor.nix
    ./modules/apps/backup.nix
    ./modules/apps/fdroid.nix
    ./modules/apps/prebuilt.nix
    ./modules/apps/updater.nix
    ./modules/apps/webview.nix
    ./modules/base.nix
    ./modules/emulator.nix
    ./modules/etc.nix
    ./modules/google.nix
    ./modules/hosts.nix
    ./modules/kernel.nix
    ./modules/microg.nix
    ./modules/release.nix
    ./modules/resources.nix
    ./modules/source.nix
    ./modules/vendor.nix
  ];
}
