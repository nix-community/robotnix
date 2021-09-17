# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{ pkgs ? (import ../../pkgs {}) }:

let
  inherit (pkgs) lib;
  robotnix = configuration: import ../../default.nix { inherit configuration pkgs; };
  devices = [ "crosshatch" "blueline" "bonito" "sargo" "coral" "flame" "sunfish" "bramble" "redfin" "barbet" ];

  deviceAttrs =
    (device: let
      aospBuild = robotnix {
        inherit device; flavor = "vanilla"; apv.enable = false;
        # Add just enough so that it creates a vendor image
        source.dirs."vendor/google_devices/${device}".src = pkgs.runCommand "empty-vendor" {} ''
          mkdir -p $out/proprietary
          cat > $out/proprietary/BoardConfigVendor.mk <<EOF
          BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
          EOF
          cat > $out/proprietary/device-vendor.mk <<EOF
          AB_OTA_PARTITIONS += vendor
          EOF
        '';
        envVars.ALLOW_MISSING_DEPENDENCIES = "true"; # Avoid warning about chre needing libadsprpc
      };
      suggestedConfig = pkgs.runCommand "${device}.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${./autogenerate.py} \
          ${aospBuild.config.device} \
          ${aospBuild.config.build.moduleInfo} \
          ${aospBuild.config.build.apv.diff}/built-files \
          ${aospBuild.config.build.apv.diff}/upstream-files \
          > $out
      '';
      suggestedBuild = robotnix { inherit device; flavor = "vanilla"; apv.customConfig = lib.importJSON suggestedConfig; };
      AOSPAllianceBuild = robotnix { inherit device; flavor = "vanilla"; };
      jsonDiff = pkgs.runCommand "${device}-suggested-apv-json.diff" {} ''
        ${pkgs.nodePackages.json-diff}/bin/json-diff ${pkgs.android-prepare-vendor.src}/${device}/config.json ${suggestedConfig} > $out || true
      '';
    in {
      inherit aospBuild;
      aospDiff = aospBuild.config.build.apv.diff;
      inherit suggestedConfig;
      inherit jsonDiff;
      inherit suggestedBuild;
      suggestedBuildDiff = suggestedBuild.config.build.apv.diff;
      AOSPAllianceBuildDiff = AOSPAllianceBuild.config.build.apv.diff;
    });
in {
  devices = lib.genAttrs devices deviceAttrs;
  combined = pkgs.runCommand "apv-generated-combined" {}
    (lib.concatMapStringsSep "\n" (device: ''
      mkdir -p $out/${device}
      cp ${(deviceAttrs device).suggestedConfig} $out/${device}/${device}.json
      cp ${(deviceAttrs device).jsonDiff} $out/${device}/${device}.json.diff
    '') devices);
}
