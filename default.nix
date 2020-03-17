{ configuration,
  pkgs ? (import ./pkgs.nix {}),
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
    ./flavors/common.nix
    ./flavors/grapheneos.nix
    ./flavors/pixel.nix
    ./flavors/vanilla.nix
    ./modules/apps/auditor.nix
    ./modules/apps/fdroid.nix
    ./modules/apps/chromium.nix
    ./modules/apps/prebuilt.nix
    ./modules/apps/seedvault.nix
    ./modules/apps/updater.nix
    ./modules/base.nix
    ./modules/emulator.nix
    ./modules/etc.nix
    ./modules/framework.nix
    ./modules/google.nix
    ./modules/hosts.nix
    ./modules/kernel.nix
    ./modules/keys.nix
    ./modules/microg.nix
    ./modules/release.nix
    ./modules/resources.nix
    ./modules/source
    ./modules/source/prebuilts.nix
    ./modules/webview.nix
    ./modules/vendor.nix
  ];
}).config
