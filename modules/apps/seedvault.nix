# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, apks, lib, ... }:

with lib;
let
  cfg = config.apps.seedvault;
in
{
  options = {
    apps.seedvault.enable = mkEnableOption "Seedvault (backup)";
  };

  config = mkIf cfg.enable (mkMerge [
  {
    # In order to switch to using this if it's not set on the first boot, run these:
    # $ bmgr list transports
    # $ bmgr transport com.stevesoltys.seedvault.transport.ConfigurableBackupTransport

    # Set as default
    resources."frameworks/base/packages/SettingsProvider".def_backup_enabled = true;
    resources."frameworks/base/packages/SettingsProvider".def_backup_transport = "com.stevesoltys.seedvault.transport.ConfigurableBackupTransport";
  }
  (mkIf (config.androidVersion >= 11) {
    # For android 11, just use the source tree from upstream, and have soong build it
    source.dirs."robotnix/seedvault".src = pkgs.fetchFromGitHub {
      owner = "stevesoltys";
      repo = "seedvault";
      rev = "e38f958f9c1fade27fcb31f2e9b273450978f70a"; # 2021-03-05
      sha256 = "1i6yx6xf59nrcsfmzwzgdp6867r9ywc8bz8qn9arhyahvzswsn5p";
    };

    product.additionalProductPackages = [ "Seedvault" ];
  })
  (mkIf (config.androidVersion == 10) {
    # For android 10, use the version built natively in nix using gradle2nix.
    apps.prebuilt.Seedvault = {
      apk = apks.seedvault_10;
      packageName = "com.stevesoltys.seedvault";
      certificate = "platform"; # Needs this certificate to use MANAGE_DOCUMENTS permission
      privileged = true;
      privappPermissions = [ "BACKUP" "MANAGE_USB" "WRITE_SECURE_SETTINGS" "INSTALL_PACKAGES" ];
    };

    etc."sysconfig/com.stevesoltys.seedvault.xml".text = ''
      <?xml version="1.0" encoding="utf-8"?>
      <config>
        <backup-transport-whitelisted-service
          service="com.stevesoltys.seedvault/.transport.ConfigurableBackupTransportService"/>
      </config>
    '';
  })
  ]);
}
