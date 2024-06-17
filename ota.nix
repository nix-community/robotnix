# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT
# I use this to generate my own OTA directory served by nginx

with (import ./pkgs { });
let
  common = {
    signing.keyStorePath = "/var/secrets/android-keys";
    signing.enable = true;
  };
in
symlinkJoin {
  name = "robotnix-ota";
  paths = [
    (import ./default.nix {
      configuration = {
        imports = [
          common
          ./example.nix
        ];
        device = "marlin";
        flavor = "vanilla";
      };
    }).otaDir
    (import ./default.nix {
      configuration = {
        imports = [
          common
          ./example.nix
        ];
        device = "crosshatch";
        flavor = "grapheneos";
      };
    }).otaDir
  ];
}
