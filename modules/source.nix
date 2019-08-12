{ config, pkgs, lib, ... }:

with lib;
let
  repo2nix = import ./repo2nix.nix;
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

      json = mkOption {
        default = json;
        internal = true;
      };

      dirs = mkOption {
        default = {};
        type = types.attrsOf (types.submodule ({ name, ... }: {
          options = {
            enable = mkOption {
              default = true;
              type = types.bool;
              description = "Include this directory in the android build source tree";
            };

            path = mkOption {
              default = name;
              type = types.str;
            };

            contents = mkOption {
              type = types.path;
            };
          };
        }));
      };

      excludeGroups = mkOption {
        default = [];
        type = types.listOf types.str;
        description = "project groups to exclude from source tree";
      };

      includeGroups = mkOption {
        default = [];
        type = types.listOf types.str;
        description = "project groups to include in source tree (overrides excludeGroups)";
      };

      patches = mkOption {
        default = [];
        type = types.listOf types.path;
      };

      unpackScript = mkOption {
        default = "";
        internal = true;
        type = types.lines;
      };

      postPatch = mkOption {
        default = "";
        internal = true;
        type = types.lines;
      };
    };
  };

  config.source = {
    excludeGroups = mkDefault [
      "darwin" # Linux-only for now
      "mips" "hikey"
      "marlin" "muskie" "wahoo" "taimen" "crosshatch" "bonito" # Exclude all devices by default
    ];
    includeGroups = mkDefault [ config.device config.deviceFamily config.kernel.configName ]; # But include the one we care about. Also include deviceFamily and kernel.configName, which might be an alternate name

    dirs = mapAttrs' (name: p:
      nameValuePair p.relpath {
        enable = mkDefault ((any (g: elem g p.groups) config.source.includeGroups) || (!(any (g: elem g p.groups) config.source.excludeGroups)));
        contents = mkDefault (projectSource p);
      }) config.source.json;

    unpackScript = (''
      mkdir -p $out

      '' +
      (concatStringsSep "" (map (d: optionalString d.enable ''
        mkdir -p $out/$(dirname ${d.path})
        echo "${d.contents} -> ${d.path}"
        cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.contents} $out/${d.path}
      '') (attrValues config.source.dirs))) +
      # Get linkfiles and copyfiles too. XXX: Hack
      (concatStringsSep "" (mapAttrsToList (name: p:
        ((concatMapStringsSep "\n" (c: ''
            mkdir -p $out/$(dirname ${c.dest})
            cp --reflink=auto $out/${p.relpath}/${c.src} $out/${c.dest}
          '') p.copyfiles) +
        (concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            ln -s ./${c.src_rel_to_dest} $out/${c.dest}
          '') p.linkfiles))
    ) config.source.json )));
  };
}
