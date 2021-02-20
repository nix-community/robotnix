# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "f4fea23153407b7448e9440c31dc0398befc00c8"; # 2021-01-04
    sha256 = "1my5kxia201sikxr2bjk5v4icw5av9c1q5v56g03zw0mmvddyv6a";
  };
in
{
  options = {
    apps.updater = {
      enable = mkEnableOption "updater";

      url = mkOption {
        type = types.str;
        description = "URL for OTA updates";
        apply = x: if hasSuffix "/" x then x else x + "/";
      };
    };
  };

  config = mkIf cfg.enable {
    source.dirs."robotnix/apps/Updater".src = src;

    # It's currently a system package in upstream
    system.additionalProductPackages = [ "Updater" ];

    resources."robotnix/apps/Updater" = {
      inherit (cfg) url;
      channel_default = config.channel;
    };
  };
}
