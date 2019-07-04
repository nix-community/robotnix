{ config, lib, ... }:

with lib;
{
  options = {
    manifest = {
      url = mkOption {
        type = types.str;
      };
      rev = mkOption {
        type = types.str;
      };
      sha256 = mkOption {
        type = types.str;
      };
    };
  };

  config.build = {
    repo2nix = import (import ../repo2nix.nix {
      inherit (config) device;
      manifest = config.manifest.url;
      inherit (config.manifest) rev sha256;
      extraFlags = "--no-repo-verify";
    });

    sourceDir = dirName: lib.findFirst (s: lib.hasSuffix ("-" + (builtins.replaceStrings ["/"] ["="] dirName)) s.outPath) null config.build.repo2nix.sources;
  };
}
