# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;

  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "55cdaf75f046929ccf898b23a1e294847be73539"; # 2021-08-25
    sha256 = "1hjh5wy4mh11svxw8qzl1fzjbwariwgc9gj3bmad92s1wy62y7rw";
  };

  relpath = (if cfg.includedInFlavor then "packages" else "robotnix") + "/apps/Updater";
in
{
  options = {
    apps.updater = {
      enable = mkEnableOption "OTA Updater";

      url = mkOption {
        type = types.str;
        description = "URL for OTA updates";
        apply = x: if lib.hasSuffix "/" x then x else x + "/";
      };

      includedInFlavor = mkOption {
        default = false;
        type = types.bool;
        internal = true;
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable (mkMerge [
      {
        resources.${relpath} = {
          inherit (cfg) url;
          channel_default = config.channel;
        };

        # TODO: It's currently on system partition in upstream. Shouldn't it be on product partition?
        system.additionalProductPackages = [ "Updater" ];

        source.dirs = mkIf (!cfg.includedInFlavor) {
          ${relpath}.src = src;
        };
      }

      # Add selinux policies
      (mkIf (!cfg.includedInFlavor && config.androidVersion >= 11) {
        source.dirs."robotnix/updater-sepolicy".src = ./updater-sepolicy;
        source.dirs."build/make".postPatch = ''
          # Originally from https://github.com/RattlesnakeOS/core-config-repo/blob/0d2cb86007c3b4df98d4f99af3dedf1ccf52b6b1/hooks/aosp_build_pre.sh
          sed -i '/product-graph dump-products/a #add selinux policies last\n$(eval include robotnix/updater-sepolicy/sepolicy.mk)' "core/config.mk"
        '';
      })
    ]))

    # Remove package if it's disabled by configuration
    (mkIf (!cfg.enable && cfg.includedInFlavor) {
      source.dirs.${relpath}.enable = false;
    })
  ];
}
