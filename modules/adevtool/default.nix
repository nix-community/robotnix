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
    buildID = lib.mkOption {
      type = lib.types.str;
      description = ''
        The build ID as specified in `build/make/core/build_id.mk` in the AOSP
        source tree.
      '';
    };
    img = lib.mkOption {
      type = lib.types.path;
      description = ''
        The vendor image to extract the vendor blobs from.
      '';
    };
    imgFilename = lib.mkOption {
      type = lib.types.str;
      description = ''
        The filename of the vendor image.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    envPackages = with pkgs; [
      # Needed for running adevtool.
      nodejs
      yarn

      # adevtool uses e2fsprogs `debugfs` to extract the vendor ext4 images.
      e2fsprogs
    ];
    source = {
      overlayfsDirs = [ "vendor/adevtool" ];
      dirs = {
        "vendor/adevtool" = {
          nativeBuildInputs = with pkgs; [ nodejs yarnConfigHook ];
          patches = [
            ./adevtool-ignore-EINVAL-upon-chown.patch
          ];
          postPatch = let
            yarnOfflineCache = pkgs.fetchYarnDeps {
              yarnLock = config.source.dirs."vendor/adevtool".manifestSrc + "/yarn.lock";
              sha256 = cfg.yarnHash;
            };
          in ''
            yarnOfflineCache=${yarnOfflineCache}
            yarnConfigHook
            mkdir -p dl
            ln -s ${cfg.img} dl/${cfg.imgFilename}
          '';
        };
      };
    };

    # The adevtool invocation is located in modules/base.nix, within the mkAndroid definition.
  };
}
