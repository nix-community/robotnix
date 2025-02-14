# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, apks, lib, robotnixlib, ... }:

let
  inherit (lib) mkIf mkOption mkEnableOption types;

  cfg = config.apps.auroraservices;
  privext = pkgs.fetchFromGitLab {
    owner = "AuroraOSS";
    repo = "AuroraServices";
    rev = "1.1.1";
    sha256 = "cYaviNIcZ03tsqLZwxSb85r04KAG6rirDL8xWFLo2ms=";
  };
in
{
  options.apps.auroraservices = {
    enable = mkEnableOption "Aurora Services";

    # See also `apps/src/main/java/org/fdroid/fdroid/data/DBHelper.java` in F-Droid source
    additionalRepos = mkOption {
      default = { };
      description = ''
        Aurora Services is a system / root application that integrates with the Aurora line of products to simplify the installation of downloaded applications.
      '';
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = { };
      }));
    };
  };

  config = mkIf cfg.enable {
    apps.prebuilt."AuroraServices" = {
      apk = apks.auroraservices;
      fingerprint = mkIf (!config.signing.enable) "7352DAE94B237866E7FB44FD94ADE44E8B6E05397E7D1FB45616A00E225063FF";
    };

    # TODO: Put this under product/
    source.dirs."robotnix/apps/AuroraServices" = {
      src = privext;
      patches = [
      ];
    };

    system.additionalProductPackages = [ "AuroraServices" ];

    etc = {
      "/system/etc/permissions/permissions_com.aurora.services.xml" = {
        partition = "system"; # TODO: Make this work in /product partition
        text = ''<?xml version="1.0" encoding="utf-8"?>
<permissions>
<privapp-permissions package="com.aurora.services">
<permission name="android.permission.DELETE_PACKAGES" />
<permission name="android.permission.INSTALL_PACKAGES" />
</privapp-permissions>
</permissions>
'';
      };
    };
  };
}
