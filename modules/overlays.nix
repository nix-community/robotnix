{ config, pkgs, lib, ... }:

with lib;
{
  options = {
    overlays = mkOption {
      default = {};
      type = types.attrsOf (types.listOf types.path);
    };
  };

  config = {
    postUnpack = concatStringsSep "\n"
      (mapAttrsToList (path: overlays: optionalString (length overlays != 0) ''
        mkdir -p ./${path}
        ${concatMapStringsSep "\n" (overlay: "cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -rv ${overlay}/* ./${path}") overlays}
      '') config.overlays);
  };
}
