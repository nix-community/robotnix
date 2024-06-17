# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  configuration,
  pkgs ? (import ./pkgs { }),
  lib ? pkgs.lib,
}:

let
  inherit (lib) mkOption types;

  eval = (
    lib.evalModules {
      modules = [
        (
          { config, ... }:
          {
            options.nixpkgs.overlays = mkOption {
              default = [ ];
              type = types.listOf types.unspecified;
              description = "Nixpkgs overlays to override the default packages used while building robotnix.";
            };

            config = {
              _module.args =
                let
                  finalPkgs = pkgs.appendOverlays config.nixpkgs.overlays;
                  apks = import ./apks { pkgs = finalPkgs; };
                  robotnixlib = import ./lib lib;
                in
                {
                  inherit apks lib robotnixlib;
                  pkgs = finalPkgs;
                };
            };
          }
        )
        configuration
        ./flavors/anbox
        ./flavors/grapheneos
        ./flavors/grapheneos/kernel.nix
        ./flavors/lineageos
        ./flavors/vanilla
        ./flavors/vanilla/10
        ./flavors/vanilla/11
        ./flavors/vanilla/11/kernel
        ./flavors/vanilla/12
        ./flavors/waydroid
        ./modules/10
        ./modules/11
        ./modules/12
        ./modules/13
        ./modules/9
        ./modules/apps/auditor.nix
        ./modules/apps/chromium.nix
        ./modules/apps/fdroid.nix
        ./modules/apps/prebuilt.nix
        ./modules/apps/seedvault.nix
        ./modules/apps/updater.nix
        ./modules/apv
        ./modules/assertions.nix
        ./modules/base.nix
        ./modules/emulator.nix
        ./modules/envpackages.nix
        ./modules/etc.nix
        ./modules/framework.nix
        ./modules/hosts.nix
        ./modules/security-pki.nix
        ./modules/kernel.nix
        ./modules/microg.nix
        ./modules/pixel
        ./modules/pixel/active-edge.nix
        ./modules/pixel/driver-binaries.nix
        ./modules/release.nix
        ./modules/resources.nix
        ./modules/signing.nix
        ./modules/source.nix
        ./modules/webview.nix
      ];
    }
  );

  # From nixpkgs/nixos/modules/system/activation/top-level.nix
  failedAssertions = map (x: x.message) (lib.filter (x: !x.assertion) eval.config.assertions);

  config =
    if failedAssertions != [ ] then
      throw "\nFailed assertions:\n${lib.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else
      lib.showWarnings eval.config.warnings eval.config;

in
{
  inherit (eval) pkgs options;
  inherit config;

  # Things that are nice to have at the top-level, since they might get moved
  # in the future:
  inherit (config.build)
    targetFiles
    unsignedTargetFiles
    signedTargetFiles
    ota
    incrementalOta
    img
    factoryImg
    bootImg
    recoveryImg
    otaDir
    releaseScript
    generateKeysScript
    verifyKeysScript
    emulator
    ;
}
