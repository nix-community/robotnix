# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ pkgs ? (import ./pkgs {}) }:

let
  lib = pkgs.lib;
  robotnix = configuration: import ./default.nix { inherit configuration pkgs; };

  configs = (lib.listToAttrs (builtins.map (c: lib.nameValuePair "${c.flavor}-${c.device}" c) [
    { device="x86_64";     flavor="vanilla"; }
    { device="arm64";      flavor="vanilla"; }
    { device="marlin";     flavor="vanilla"; androidVersion=10; } # Out-of-date
    { device="sailfish";   flavor="vanilla"; androidVersion=10; } # Out-of-date
    { device="taimen";     flavor="vanilla"; androidVersion=11; } # Out-of-date
    { device="walleye";    flavor="vanilla"; androidVersion=11; } # Out-of-date
    { device="crosshatch"; flavor="vanilla"; }
    { device="blueline";   flavor="vanilla"; }
    { device="bonito";     flavor="vanilla"; }
    { device="sargo";      flavor="vanilla"; }
    { device="coral";      flavor="vanilla"; }
    { device="flame";      flavor="vanilla"; }
    { device="sunfish";    flavor="vanilla"; }
    { device="bramble";    flavor="vanilla"; }
    { device="redfin";     flavor="vanilla"; }
    { device="barbet";     flavor="vanilla"; }
    { device="raven";      flavor="vanilla"; }
    { device="oriole";     flavor="vanilla"; }

    { device="x86_64";     flavor="grapheneos"; }
    { device="arm64";      flavor="grapheneos"; }
    { device="crosshatch"; flavor="grapheneos"; }
    { device="blueline";   flavor="grapheneos"; }
    { device="bonito";     flavor="grapheneos"; }
    { device="sargo";      flavor="grapheneos"; }
    { device="coral";      flavor="grapheneos"; }
    { device="flame";      flavor="grapheneos"; }
    { device="sunfish";    flavor="grapheneos"; }
    { device="bramble";    flavor="grapheneos"; }
    { device="redfin";     flavor="grapheneos"; }
    { device="barbet";     flavor="grapheneos"; }

    { device="marlin";     flavor="lineageos"; }
    { device="pioneer";    flavor="lineageos"; }

    { device="x86_64";     flavor="anbox"; }
    { device="arm64";      flavor="anbox"; }
  ]));

  builtConfigs = lib.mapAttrs (name: c: robotnix c) configs;

  defaultBuild = robotnix { device="arm64"; flavor="vanilla"; };

  tests = {
    attestation-server = (import ./nixos/attestation-server/test.nix { inherit pkgs; }) {};

    generateKeys = let
      inherit ((robotnix { device="crosshatch"; flavor="vanilla"; }))
        generateKeysScript verifyKeysScript;
    in pkgs.runCommand "test-generate-keys" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
      mkdir -p $out
      cd $out
      shellcheck ${generateKeysScript}
      shellcheck ${verifyKeysScript}

      ${verifyKeysScript} $PWD && exit 1 || true # verifyKeysScript should fail if we haven't generated keys yet
      ${generateKeysScript} $PWD
      ${verifyKeysScript} $PWD
    '';
  };

  # TODO: Reunify with module in reproducibility reports
  snakeoilSignedModule = { config, ... }: let
    snakeoilKeys = pkgs.runCommand "snakeoil-keys" {} ''
      mkdir -p $out
      ${config.build.generateKeysScript} $out
    '';
  in {
    signing.enable = true;
    signing.keyStorePath = snakeoilKeys;
    signing.buildTimeKeyStorePath = "${snakeoilKeys}";
  };
in
{
  inherit (pkgs) diffoscope;

  check = lib.mapAttrs (name: c: (robotnix c).config.build.checkAndroid) configs;

  imgs = lib.recurseIntoAttrs (lib.mapAttrs (name: c: c.img) builtConfigs);

  # Generates img and ota files for each configuration using snakeoil keys
  signingCheck = lib.mapAttrs (name: c: { inherit (robotnix { imports = [ snakeoilSignedModule c ]; }) img ota; }) {
    "lineageos-10" = { device="marlin"; flavor="lineageos"; androidVersion=10; };
    "vanilla-10" = { device="sunfish"; flavor="vanilla"; androidVersion=10; apv.enable=false; pixel.useUpstreamDriverBinaries=true; }; # APV not working on Android 10...
    "vanilla-11" = { device="sunfish"; flavor="vanilla"; androidVersion=11; };
    "vanilla-12" = { device="sunfish"; flavor="vanilla"; androidVersion=12; };
  };

  lineageosImgs = let
    deviceMetadata = lib.importJSON ./flavors/lineageos/device-metadata.json;
  in lib.dontRecurseIntoAttrs (lib.mapAttrs (name: x: (robotnix { device=name; flavor="lineageos"; }).img) deviceMetadata);

  # For testing instantiation
  vanilla-arm64 = lib.recurseIntoAttrs {
    inherit (defaultBuild)
      targetFiles ota img factoryImg bootImg otaDir
      releaseScript;
  };

  sdk = import ./sdk;

  grapheneos-emulator = (robotnix { device="x86_64"; flavor="grapheneos"; }).emulator;
  vanilla-emulator = (robotnix { device="x86_64"; flavor="vanilla"; }).emulator;
  vanilla-12-emulator = (robotnix { device="x86_64"; flavor="vanilla"; productNamePrefix="sdk_phone_"; androidVersion=12; }).emulator;
  danielfullmer-emulator = (robotnix { device="x86_64"; flavor="grapheneos"; imports = [ ./example.nix ]; apps.auditor.enable = lib.mkForce false; }).emulator;

  tests = lib.recurseIntoAttrs tests;

  # Stuff to upload to binary cache
  cached = lib.recurseIntoAttrs {
    browsers = lib.recurseIntoAttrs {
      inherit ((robotnix { device = "arm64"; flavor="vanilla"; }).config.build)
        chromium;
      inherit ((robotnix { device = "arm64"; flavor="vanilla"; apps.bromite.enable=true; webview.bromite.enable=true; }).config.build)
        bromite;
      inherit ((robotnix { device = "arm64"; flavor="grapheneos"; }).config.build)
        vanadium;
    };

    kernels = lib.recurseIntoAttrs
      (lib.mapAttrs (name: c: c.config.build.kernel)
        (lib.filterAttrs (name: c: c.config.kernel.enable) builtConfigs));

    tests = lib.recurseIntoAttrs {
      attestation-server = tests.attestation-server.test;
      inherit (tests) generateKeys;
    };

    packages = lib.recurseIntoAttrs {
      inherit (pkgs) cipd;
    };
  };
}
