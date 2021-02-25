# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

with lib;
{
  options = {
    hosts = mkOption {
      default = null;
      type = types.nullOr types.path;
      description = "Custom hosts file";
    };
  };

  config = mkIf (config.hosts != null) {
    # TODO: Replace with resource overlay?
    source.dirs."system/core".postPatch = ''
      cp -v ${config.hosts} rootdir/etc/hosts
    '';
  };
}
