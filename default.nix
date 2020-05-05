{ configuration,
  pkgs ? (import ./pkgs {}),
  lib ? pkgs.stdenv.lib
}:

let
  robotnixlib = import ./lib lib;
  apks = import ./apks { inherit pkgs; };
in
(lib.evalModules {
  modules = [
    { _module.args = {
        inherit pkgs apks lib robotnixlib;
      };
    }
    configuration 
    ./flavors/grapheneos
    ./flavors/lineageos
    ./flavors/vanilla
    ./modules/apps/auditor.nix
    ./modules/apps/chromium.nix
    ./modules/apps/fdroid.nix
    ./modules/apps/prebuilt.nix
    ./modules/apps/seedvault.nix
    ./modules/apps/updater.nix
    ./modules/base.nix
    ./modules/common.nix
    ./modules/emulator.nix
    ./modules/etc.nix
    ./modules/framework.nix
    ./modules/google.nix
    ./modules/hosts.nix
    ./modules/kernel.nix
    ./modules/keys.nix
    ./modules/microg.nix
    ./modules/pixel
    ./modules/release.nix
    ./modules/resources.nix
    ./modules/source.nix
    ./modules/vendor.nix
    ./modules/webview.nix
  ];
}).config
