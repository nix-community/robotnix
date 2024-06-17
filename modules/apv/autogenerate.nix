# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{
  pkgs ? (import ../../pkgs { }),
}:

let
  inherit (pkgs) lib;
  robotnix = configuration: import ../../default.nix { inherit configuration pkgs; };
  devices = [
    "crosshatch"
    "blueline"
    "bonito"
    "sargo"
    "coral"
    "flame"
    "sunfish"
    "bramble"
    "redfin"
    "barbet"
    "raven"
    "oriole"
  ];

  deviceAttrs = (
    device:
    let
      aospBuild = robotnix {
        inherit device;
        flavor = "vanilla";
        apv.enable = false;
        # Add just enough so that it creates a vendor image
        source.dirs."vendor/google_devices/${device}".src = pkgs.runCommand "empty-vendor" { } ''
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
      suggestedConfig =
        pkgs.runCommand "${device}-config.json" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
              find ${pkgs.robotnix.unpackImg aospBuild.config.apv.img} -type f -printf "%P\n" | sort > upstream-files
              find ${pkgs.robotnix.unpackImg aospBuild.img} -type f -printf "%P\n" | sort > built-files

              python3 ${./autogenerate.py} \
                ${aospBuild.config.device} \
                ${aospBuild.config.build.moduleInfo} \
                built-files \
                upstream-files \
                > config.json

            ${pkgs.jq}/bin/jq -s '.[0] * .[1]' ${pkgs.android-prepare-vendor.src}/${device}/config.json config.json > $out
          '';
      suggestedBuild = robotnix {
        inherit device;
        flavor = "vanilla";
        apv.customConfig = lib.importJSON suggestedConfig;
      };
      AOSPAllianceBuild = robotnix {
        inherit device;
        flavor = "vanilla";
      };
      jsonDiff = pkgs.runCommand "${device}-suggested-apv-json.diff" { } ''
        ${pkgs.nodePackages.json-diff}/bin/json-diff ${pkgs.android-prepare-vendor.src}/${device}/config.json ${suggestedConfig} > $out || true
      '';
    in
    {
      inherit aospBuild;
      inherit suggestedConfig;
      inherit jsonDiff;
      inherit suggestedBuild;
      aospDiff = pkgs.robotnix.compareImagesQuickDiff aospBuild.config.apv.img aospBuild.img;
      suggestedBuildDiff = pkgs.robotnix.compareImagesQuickDiff suggestedBuild.config.apv.img suggestedBuild.img;
    }
  );
in
{
  devices = lib.genAttrs devices deviceAttrs;
  combined = pkgs.runCommand "apv-generated-combined" { } (
    lib.concatMapStringsSep "\n" (device: ''
      mkdir -p $out/${device}
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' ${pkgs.android-prepare-vendor.src}/${device}/config.json ${(deviceAttrs device).suggestedConfig} > $out/${device}/config.json
    '') devices
  );
}
