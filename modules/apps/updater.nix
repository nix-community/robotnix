# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;

  cfg = config.apps.updater;

  src =
    if config.androidVersion < 12 then
      pkgs.fetchFromGitHub {
        owner = "GrapheneOS";
        repo = "platform_packages_apps_Updater";
        rev = "55cdaf75f046929ccf898b23a1e294847be73539"; # 2021-08-25
        sha256 = "1hjh5wy4mh11svxw8qzl1fzjbwariwgc9gj3bmad92s1wy62y7rw";
      }
    else
      pkgs.fetchFromGitHub {
        owner = "GrapheneOS";
        repo = "platform_packages_apps_Updater";
        rev = "95bcc5ae29cf28fe4b575ae480de080a6c036480"; # 2021-10-26
        sha256 = "161140fsxwcndxx5aqcm3f3z2zcpaa0x02hdnkg45a1nll2gn5x7";
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

      flavor = mkOption {
        type = types.enum [ "grapheneos" "lineageos" ];
        default = "grapheneos";
        description = ''
          Which updater package to use, and which kind of metadata to generate for it.
        '';
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
        # TODO: It's currently on system partition in upstream. Shouldn't it be on product partition?
        system.additionalProductPackages = [ "Updater" ];
      }

      (mkIf (cfg.flavor == "grapheneos") {
        resources.${relpath} = {
          inherit (cfg) url;
          channel_default = config.channel;
        };

        source.dirs = mkIf (!cfg.includedInFlavor) (mkMerge [
          {
            ${relpath}.src = src;
          }
          (mkIf (!cfg.includedInFlavor && config.androidVersion >= 11) {
            # Add selinux policies
            "robotnix/updater-sepolicy".src = ./updater-sepolicy;
            "build/make".postPatch = ''
              # Originally from https://github.com/RattlesnakeOS/core-config-repo/blob/0d2cb86007c3b4df98d4f99af3dedf1ccf52b6b1/hooks/aosp_build_pre.sh
              sed -i '/product-graph dump-products/a #add selinux policies last\n$(eval include robotnix/updater-sepolicy/sepolicy.mk)' "core/config.mk"
            '';
          })
        ]);
      })

      (mkIf (cfg.flavor == "lineageos") {
        resources."packages/apps/Updater" = mkIf (cfg.flavor == "lineageos") {
          updater_server_url = "${cfg.url}lineageos-${config.device}.json";
        };
      })
    ]))

    # Remove package if it's disabled by configuration
    (mkIf (!cfg.enable && cfg.includedInFlavor) {
      source.dirs.${relpath}.enable = false;
    })
  ];
}
