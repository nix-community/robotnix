{ config, pkgs, lib, ... }:

with lib;
{
  options = {
    hosts = mkOption {
      type = types.path;
      description = "Custom hosts file";
    };
  };

  config = {
    postPatch = ''
      cp -v ${config.hosts} system/core/rootdir/etc/hosts
    '';
  };
}
