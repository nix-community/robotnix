{ configuration,
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.stdenv.lib
}:

lib.evalModules {
  modules = [
    { _module.args.pkgs = pkgs; _module.args.lib = lib; }
    configuration 
    ./modules/apps/backup.nix
    ./modules/apps/fdroid.nix
    ./modules/apps/updater.nix
    ./modules/apps/webview.nix
    ./modules/base.nix
    ./modules/kernel.nix
    ./modules/release.nix
    ./modules/source.nix
    ./modules/vendor.nix
  ];
}
