{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.backup;
  src = (pkgs.fetchFromGitHub {
    owner = "stevesoltys";
    repo = "backup";
    rev = "0.3.0";
    sha256 = "14dc2s4x75hj6hfz4v8dr0m6zh7m8c7zwqlmq9qviql1fa6hslvx";
  });
in
{
  options = {
    apps.backup.enable = mkEnableOption "Backup";
  };

  config = mkIf cfg.enable {
    overlays."packages/apps/Backup" = [ src ];

    additionalProductPackages = [ "Backup" ];
  };
}
