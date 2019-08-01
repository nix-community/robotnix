{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.backup;
  backup = pkgs.callPackage ./backup {};
in
{
  options = {
    apps.backup.enable = mkEnableOption "Backup";
  };

  config = mkIf cfg.enable {
    apps.prebuilt.Backup = {
      apk = backup;
      packageName = "com.stevesoltys.backup";
      privileged = true; # Is this needed? it's not in the upstream repo.
      privappPermissions = [ "BACKUP" ];
      extraConfig = "LOCAL_DEX_PREOPT := false";
    };

    etc."sysconfig/com.stevesoltys.backup.xml".text = ''
      <?xml version="1.0" encoding="utf-8"?>
      <config>
        <backup-transport-whitelisted-service
          service="com.stevesoltys.backup/.transport.ConfigurableBackupTransportService"/>
      </config>
    '';
  };
}
