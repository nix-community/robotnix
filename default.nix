{ configuration,
  pkgs ? import ./pkgs.nix,
  lib ? pkgs.stdenv.lib
}:

let
  nixdroidlib = import ./lib lib;
  apks = import ./apks { inherit pkgs; };
in
(lib.evalModules {
  modules = [
    { _module.args = {
        inherit pkgs apks lib nixdroidlib;
      };
    }
    configuration 
    ./flavors/grapheneos.nix
    ./flavors/vanilla.nix
    ./flavors/common.nix
    ./flavors/pixel.nix
    ./modules/apps/auditor.nix
    ./modules/apps/fdroid.nix
    ./modules/apps/prebuilt.nix
    ./modules/apps/seedvault.nix
    ./modules/apps/updater.nix
    ./modules/apps/webview.nix
    ./modules/base.nix
    ./modules/emulator.nix
    ./modules/etc.nix
    ./modules/framework.nix
    ./modules/google.nix
    ./modules/hosts.nix
    ./modules/kernel.nix
    ./modules/microg.nix
    ./modules/release.nix
    ./modules/resources.nix
    ./modules/source
    ./modules/vendor.nix
  ];
}).config
