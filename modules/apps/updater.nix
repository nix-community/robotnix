{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "d3ee2c407d15b34923aaeb376e2cab09d9d7fd14"; # 2019-06-20
    sha256 = "0h8sicfk7n67z4lhziv5052zf3d30pgqdka1f8qwm1vqrj525hza";
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

    resources."nixdroid/apps/Updater".url = cfg.url;
  };
}
