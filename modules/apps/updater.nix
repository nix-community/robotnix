{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "96d1642680a3207c45ce6a7a60cadda885b87604"; # 2020-04-08
    sha256 = "06i1szgyrf09hrjmf5aqy5mmd491ylwd0xpxp1f9l1njgpg0l6k8";
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
