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
    source.postPatch = ''
      cp -v ${config.hosts} system/core/rootdir/etc/hosts
    '';
  };
}
