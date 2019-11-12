{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.seedvault;
  seedvault = pkgs.callPackage ./seedvault {};
in
{
  options = {
    apps.seedvault.enable = mkEnableOption "Seedvault (backup)";
  };

  config = mkIf cfg.enable {
    apps.prebuilt.Seedvault = {
      apk = seedvault;
      packageName = "com.stevesoltys.seedvault";
      privileged = true; # Is this needed? it's not in the upstream repo.
      privappPermissions = [ "BACKUP" "MANAGE_USB" "WRITE_SECURE_SETTINGS" ];
    };

    etc."sysconfig/com.stevesoltys.seedvault.xml".text = ''
      <?xml version="1.0" encoding="utf-8"?>
      <config>
        <backup-transport-whitelisted-service
          service="com.stevesoltys.seedvault/.transport.ConfigurableBackupTransportService"/>
      </config>
    '';

    # Set as default
    resources."frameworks/base/packages/SettingsProvider".def_backup_transport = "com.stevesoltys.seedvault/.transport.ConfigurableBackupTransportService";

    # TODO: is the above working?
    # Run bmgr list transports
    # or bmgr set transport com.stevesoltys.seedvault.transport.ConfigurableBackupTransport
  };
}
