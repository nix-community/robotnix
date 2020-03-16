{ config, pkgs, apks, lib, ... }:

with lib;
let
  cfg = config.apps.seedvault;
in
{
  options = {
    apps.seedvault.enable = mkEnableOption "Seedvault (backup)";
  };

  config = mkIf cfg.enable {
    apps.prebuilt.Seedvault = {
      apk = apks.seedvault;
      packageName = "com.stevesoltys.seedvault";
      privileged = true;
      privappPermissions = [ "BACKUP" "MANAGE_USB" "MANAGE_DOCUMENTS" "WRITE_SECURE_SETTINGS" "INSTALL_PACKAGES" ];
    };

    etc."sysconfig/com.stevesoltys.seedvault.xml".text = ''
      <?xml version="1.0" encoding="utf-8"?>
      <config>
        <backup-transport-whitelisted-service
          service="com.stevesoltys.seedvault.transport.ConfigurableBackupTransportService"/>
      </config>
    '';

    # Set as default
    resources."frameworks/base/packages/SettingsProvider".def_backup_transport = "com.stevesoltys.seedvault.transport.ConfigurableBackupTransportService";

    # TODO: is the above working?
    # $ bmgr list transports
    # $ bmgr transport com.stevesoltys.seedvault.transport.ConfigurableBackupTransport
  };
}
