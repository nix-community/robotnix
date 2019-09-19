{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "b45f0757093e0f3bcc4cb5823d6bb6b14ca2beb8"; # 2019-08-25
    sha256 = "0zwdv130sfkxya0wqpw9dg4s98hx97j2shg9s3ri9q66s3jy95xr";
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
    source.dirs."nixdroid/apps/Updater".contents = src;

    additionalProductPackages = [ "Updater" ];

    resources."nixdroid/apps/Updater" = {
      inherit (cfg) url;
      channel_default = config.channel;
    };
  };
}
