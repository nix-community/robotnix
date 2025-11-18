# SPDX-FileCopyrightText: 2025 cyclopentane and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, lib, pkgs, ... }:
let
  cfg = config.adevtool;
in {
  options.adevtool = {
    enable = lib.mkEnableOption "the adevtool module";
    yarnHash = lib.mkOption {
      type = lib.types.str;
      description = ''
        The yarn hash of the `yarn.lock` file inside the `vendor/adevtool` repo
        in the source tree, as required by `fetchYarnDeps`.
      '';
    };
    devices = lib.mkOption {
      type = with lib.types; listOf str;
      description = ''
        The device codenames to extract the vendor blobs for.
      '';
    };
    vendorImgMetadata = lib.mkOption {
      type = with lib.types; listOf (submodule {
        options = {
          fileName = lib.mkOption {
            type = str;
            description = ''
              The file name of the image.
            '';
          };
          url = lib.mkOption {
            type = str;
            description = ''
              The download URL of the image.
            '';
          };
          sha256 = lib.mkOption {
            type = str;
            description = ''
              The SHA256 sum of the image.
            '';
          };
        };
      });
      default = [];
      description = ''
        The metadata of the vendor images to be prefetched and made available
        to adevtool during the build. The adevtool module will add the
        corresponding instances of `pkgs.fetchurl` to `adevtool.vendorImgs`.
      '';
    };

    vendorImgs = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = ''
        The vendor images to be prefetched and made available to adevtool
        during the build.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    envPackages = with pkgs; [
      # Needed for running adevtool.
      nodejs

      # adevtool uses e2fsprogs `debugfs` to extract the vendor ext4 images.
      e2fsprogs
    ];
    source = {
      dirs = {
        "vendor/adevtool" = {
          nativeBuildInputs = with pkgs; [ nodejs yarnConfigHook ];
          postPatch = let
            yarnOfflineCache = pkgs.fetchYarnDeps {
              yarnLock = config.source.dirs."vendor/adevtool".manifestSrc + "/yarn.lock";
              sha256 = cfg.yarnHash;
            };
          in ''
            yarnOfflineCache=${yarnOfflineCache}
            yarnConfigHook
          '';
        };
      };
    };

    adevtool.vendorImgs = builtins.listToAttrs (builtins.map (metadata: {
      name = metadata.fileName;
      value = pkgs.fetchurl {
        inherit (metadata) url sha256;
      };
    }) config.adevtool.vendorImgMetadata);

    build.vendorImgDir = pkgs.linkFarm "vendor-imgs" config.adevtool.vendorImgs;

    # The adevtool invocation is located in modules/base.nix, within the mkAndroid definition.
  };
}
