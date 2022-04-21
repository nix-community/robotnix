# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
{
  options = {
    adevtool = {
      enable = lib.mkEnableOption "adevtool";
    };
  };

  config = lib.mkIf config.adevtool.enable {
    source.dirs."vendor/test".src = pkgs.runCommand "test" {} ''
      mkdir -p hardware/google
      cp -a ${config.source.dirs."hardware/google/pixel-sepolicy".src} hardware/google/pixel-sepolicy
      chmod u+w hardware/google/pixel-sepolicy -R

      mkdir -p device/google
      cp -a ${config.source.dirs."device/google/gs101-sepolicy".src} device/google/gs101-sepolicy
      chmod u+w device/google/gs101-sepolicy -R

      ${pkgs.adevtool}/bin/adevtool \
        generate-all \
        ${pkgs.adevtool.src}/config/pixel/${config.device}.yml \
        -c ${config.source.dirs."vendor/state".src}/${config.device}-state-output-file.json \
        -s ${config.build.apv.unpackedImg} \
        -a ${pkgs.robotnix.build-tools}/aapt2

      mkdir $out
      mv vendor $out
      mv hardware $out
      mv device $out
    '';
  };
}
