{ config, pkgs, lib, ... }:

with lib;
let
  repo2nix = import ../repo2nix.nix;
  jsonFile = repo2nix {
    manifest = config.source.manifest.url;
    inherit (config.source.manifest) rev sha256;
    extraFlags = "--no-repo-verify";
  };
  json = builtins.fromJSON (builtins.readFile jsonFile);
  # Get project source from JSON description
  projectSource = p: builtins.fetchGit {
    inherit (p) url rev;
    ref = if strings.hasInfix "refs/heads" p.revisionExpr then last (splitString "/" p.revisionExpr) else p.revisionExpr;
    name = builtins.replaceStrings ["/"] ["="] p.relpath;
  };
in
{
  options = {
    source = {
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
      dirs = mkOption {
        #type = types.attrsOf types.path;
        default = mapAttrs' (name: p: nameValuePair p.relpath (projectSource p)) json;
        internal = true;
      };
    };
  };

  config.build = {
    source = pkgs.runCommand "${config.device}-${config.buildID}-src" {} (''
      mkdir -p $out

      '' +
      (concatStringsSep "\n" (mapAttrsToList (dirname: src: ''
        mkdir -p $out/$(dirname ${dirname})
        cp --reflink=auto -r ${src} $out/${dirname}
      '') config.source.dirs)) +
      # Get linkfiles and copyfiles too. XXX: Hack
      (concatStringsSep "\n" (mapAttrsToList (name: p:
        ((concatMapStringsSep "\n" (c: ''
            mkdir -p $out/$(dirname ${c.dest})
            cp --reflink=auto $out/${p.relpath}/${c.src} $out/${c.dest}
          '') p.copyfiles) +
        (concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            ln -s ./${c.src_rel_to_dest} $out/${c.dest}
          '') p.linkfiles))
       ) json )));
  };
}
