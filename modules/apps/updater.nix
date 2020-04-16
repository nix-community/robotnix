{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "a000bbabc368d08f4816d919bd979495e8552a72"; # 2019-10-09
    sha256 = "01mlb8xr2jj3db6p3rpc3pbrb1kixd50vnflmjzb3yn4hxcmsv7v";
  };
in
{
  options = {
    apps.updater = {
      enable = mkEnableOption "updater";

      url = mkOption {
        type = types.str;
        description = "URL for OTA updates (requires trailing slash)";
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
