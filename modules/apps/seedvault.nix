# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  apks,
  lib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkEnableOption
    types
    ;

  cfg = config.apps.seedvault;
in
{
  options = {
    apps.seedvault = {
      enable = mkEnableOption "Seedvault (backup)";

      includedInFlavor = mkOption {
        default = false;
        type = types.bool;
        internal = true;
      };
    };
  };

  config = mkIf (cfg.enable && (!cfg.includedInFlavor)) (mkMerge [
    {
      # In order to switch to using this if it's not set on the first boot, run these:
      # $ bmgr list transports
      # $ bmgr transport com.stevesoltys.seedvault.transport.ConfigurableBackupTransport

      # Set as default
      resources."frameworks/base/packages/SettingsProvider".def_backup_enabled = true;
      resources."frameworks/base/packages/SettingsProvider".def_backup_transport = "com.stevesoltys.seedvault.transport.ConfigurableBackupTransport";
    }
    (mkIf (config.androidVersion == 12) {
      # For android 11, just use the source tree from upstream, and have soong build it
      source.dirs."robotnix/seedvault".src = pkgs.fetchFromGitHub {
        owner = "seedvault-app";
        repo = "seedvault";
        rev = "b0c6eeb9f7af7845cabdac58a87f183551a053a1"; # 2021-10-23
        sha256 = "0fc7bq8wmav25cb51s7hidrbdb17wq03naymclqbwsc9pxrv4px6";
      };
      source.dirs."robotnix/seedvault".patches = [ ./seedvault-12.patch ];

      # TODO: Move to product partition?
      system.additionalProductPackages = [ "Seedvault" ];
    })
    (mkIf (config.androidVersion == 11) {
      # For android 11, just use the source tree from upstream, and have soong build it
      source.dirs."robotnix/seedvault".src = pkgs.fetchFromGitHub {
        owner = "seedvault-app";
        repo = "seedvault";
        rev = "11-2.3"; # 2021-10-04
        sha256 = "0blqjm5zamam1imzgpkwyvg6n6c2aa9cj5kvcjj44a9glyyqqmry";
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
        privappPermissions = [
          "BACKUP"
          "MANAGE_USB"
          "WRITE_SECURE_SETTINGS"
          "INSTALL_PACKAGES"
        ];
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
