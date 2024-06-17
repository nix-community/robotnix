# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  pkgs ? (import ./pkgs { }),
}:

let
  lib = pkgs.lib;
  robotnix = configuration: import ./default.nix { inherit configuration pkgs; };
  configs = import ./configs.nix { inherit lib; };
  builtConfigs = lib.mapAttrs (name: c: robotnix c) configs;
  defaultBuild = robotnix {
    device = "arm64";
    flavor = "vanilla";
  };

  tests = {
    attestation-server = (import ./nixos/attestation-server/test.nix { inherit pkgs; }) { };

    generateKeys =
      let
        inherit
          (
            (robotnix {
              device = "crosshatch";
              flavor = "vanilla";
            })
          )
          generateKeysScript
          verifyKeysScript
          ;
      in
      pkgs.runCommand "test-generate-keys" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
        mkdir -p $out
        cd $out
        shellcheck ${generateKeysScript}
        shellcheck ${verifyKeysScript}

        ${verifyKeysScript} $PWD && exit 1 || true # verifyKeysScript should fail if we haven't generated keys yet
        ${generateKeysScript} $PWD
        ${verifyKeysScript} $PWD
      '';
  };

in
{
  inherit (pkgs) diffoscope;

  imgs = lib.recurseIntoAttrs (lib.mapAttrs (name: c: c.img) builtConfigs);

  # For testing instantiation
  vanilla-arm64 = lib.recurseIntoAttrs {
    inherit (defaultBuild)
      ota
      img
      factoryImg
      bootImg
      otaDir
      releaseScript
      ;
  };

  sdk = import ./sdk;

  grapheneos-emulator =
    (robotnix {
      device = "x86_64";
      flavor = "grapheneos";
    }).emulator;
  vanilla-emulator =
    (robotnix {
      device = "x86_64";
      flavor = "vanilla";
    }).emulator;
  vanilla-12-emulator =
    (robotnix {
      device = "x86_64";
      flavor = "vanilla";
      productNamePrefix = "sdk_phone_";
      androidVersion = 12;
    }).emulator;
  danielfullmer-emulator =
    (robotnix {
      device = "x86_64";
      flavor = "grapheneos";
      imports = [ ./example.nix ];
      apps.auditor.enable = lib.mkForce false;
    }).emulator;

  inherit tests;

  # Stuff to upload to binary cache
  cached = lib.recurseIntoAttrs {
    browsers = lib.recurseIntoAttrs {
      inherit
        ((robotnix {
          device = "arm64";
          flavor = "vanilla";
        }).config.build
        )
        chromium
        ;
      inherit
        ((robotnix {
          device = "arm64";
          flavor = "vanilla";
          apps.bromite.enable = true;
          webview.bromite.enable = true;
        }).config.build
        )
        bromite
        ;
      inherit
        ((robotnix {
          device = "arm64";
          flavor = "grapheneos";
        }).config.build
        )
        vanadium
        ;
    };

    kernels = lib.recurseIntoAttrs (
      (lib.mapAttrs (name: c: c.config.build.kernel) (
        lib.filterAttrs (name: c: c.config.kernel.enable) builtConfigs
      ))
    );

    tests = lib.recurseIntoAttrs {
      attestation-server = tests.attestation-server.test;
      inherit (tests) generateKeys;
    };

    packages = lib.recurseIntoAttrs { inherit (pkgs) cipd; };
  };
}
