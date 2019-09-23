{ config, pkgs, lib, ... }:

with lib;
let
  repo2nix = import ./repo2nix.nix;
  jsonFile = repo2nix {
    manifest = config.source.manifest.url;
    inherit (config.source.manifest) rev sha256 localManifests;
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

        localManifests = mkOption {
          default = [];
          type = types.listOf types.path;
        };
      };

      json = mkOption {
        default = json;
        internal = true;
      };

      dirs = mkOption {
        default = {};
        type = types.attrsOf (types.submodule ({ name, config, ... }: {
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

            patches = mkOption {
              default = [];
              type = types.listOf types.path;
            };

            postPatch = mkOption {
              default = "";
              type = types.lines;
            };

            patchedContents = mkOption {
              type = types.path;
              internal = true;
            };
          };

          config = {
            patchedContents = mkDefault (if (config.patches != [] || config.postPatch != "") then
              (pkgs.runCommand "${builtins.replaceStrings ["/"] ["="] config.path}-patched" {} ''
                cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.contents} $out/
                chmod u+w -R $out
                ${concatMapStringsSep "\n" (p: "patch -p1 --no-backup-if-mismatch -d $out < ${p}") config.patches}
                cd $out
                ${config.postPatch}
              '')
              else config.contents);
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

      unpackScript = mkOption {
        default = "";
        internal = true;
        type = types.lines;
      };
    };
  };

  config.source = mkMerge [{
    dirs = mapAttrs' (name: p:
      nameValuePair p.relpath {
        enable = mkDefault ((any (g: elem g p.groups) config.source.includeGroups) || (!(any (g: elem g p.groups) config.source.excludeGroups)));
        contents = mkDefault (projectSource p);
      }) config.source.json;

    unpackScript = (
      (concatStringsSep "\n" (map (d: optionalString d.enable ''
        if [[ $useBindMounts = true ]]; then
          mkdir -p ${d.path}
          ${pkgs.utillinux}/bin/mount --bind ${d.patchedContents} ${d.path}
        else
          echo "${d.contents} -> ${d.path}"
          mkdir -p $(dirname ${d.path})
          cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.patchedContents} ${d.path}/
          chmod -R u+w ${d.path}
        fi
      '') (attrValues config.source.dirs))) +
      (concatStringsSep "" (mapAttrsToList (name: p: optionalString config.source.dirs.${p.relpath}.enable
        ((concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            cp --reflink=auto ${p.relpath}/${c.src} ${c.dest}
          '') p.copyfiles) +
        (concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            ln -s ./${c.src_rel_to_dest} ${c.dest}
          '') p.linkfiles))
      ) config.source.json)));
    }
    {
      unpackScript = mkBefore ''
        export useBindMounts=$(test -e /dev/fuse && echo true)

        if [[ $useBindMounts = true ]]; then
          echo " - Found /dev/fuse. Using bind-mounts and bindfs instead of copying source files"
          mkdir -p bind-mounts src
          cd bind-mounts
        else
          echo " - Could not find /dev/fuse. Copying source files instead of using bind-mounts"
        fi
      '';
    }
    {
      unpackScript = mkAfter ''
        if [[ $useBindMounts = true ]]; then
          cd ..
          ${pkgs.bindfs}/bin/bindfs --perms=u+w bind-mounts src
          export sourceRoot=$PWD/src
        fi
      '';
    }
  ];

  # Extract only files under nixdroid/ (for debugging with an external AOSP build)
  config.build.debugUnpackScript = pkgs.writeText "unpack.sh" (''
    rm -rf nixdroid
    '' +
    (concatStringsSep "" (map (d: optionalString (d.enable && (hasPrefix "nixdroid/" d.path)) ''
      mkdir -p $(dirname ${d.path})
      echo "${d.contents} -> ${d.path}"
      cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.contents} ${d.path}/
    '') (attrValues config.source.dirs))) + ''
    chmod -R u+w nixdroid/
  '');
}
