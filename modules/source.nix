{ config, pkgs, lib, ... }:

with lib;
let
  repo2nix = import ./repo2nix.nix;
  json = importJSON config.source.jsonFile; # Get project source from JSON description

  projectSource = p:
    let
      ref = if strings.hasInfix "refs/heads" p.revisionExpr then last (splitString "/" p.revisionExpr) else p.revisionExpr;
      name = builtins.replaceStrings ["/"] ["="] p.relpath;
    in
    if config.source.evalTimeFetching
    then
      builtins.fetchGit { # Evaluation-time source fetching. Uses nix's git cache, but any nix-instantiate will require fetching sources.
        inherit (p) url rev;
        inherit ref name;
      }
    else
      pkgs.fetchgit { # Build-time source fetching. This should be preferred, but is slightly less convenient when developing.
        inherit (p) url rev sha256;
        # Submodules are manually specified as "nested projects". No support for that in repo2nix. See https://gerrit.googlesource.com/git-repo/+/master/docs/manifest-format.md
        fetchSubmodules = false;
        deepClone = false;
      };
in
{
  options = {
    source = {
      # End-user should either set source.manifest.* or source.jsonFile
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

      evalTimeFetching = mkOption {
        default = false;
        description = ''
          Set config.source.jsonFile automatically using IFD with information
          from `source.manifest`. Also enables use of builtins.fetchGit instead
          of pkgs.fetchgit if not all sha256 hashes are available. (Useful for
          development)
        '';
      };

      jsonFile = mkOption {
        type = types.path;
        description = "Path to JSON file, outputted by mk-repo-file.py or with repo2nix";
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

            contents = mkOption { # TODO: Rename just "src"?
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

  config.source = {
    jsonFile = mkIf config.source.evalTimeFetching (repo2nix {
      manifest = config.source.manifest.url;
      inherit (config.source.manifest) rev sha256 localManifests;
    });

    dirs = mapAttrs' (name: p:
      nameValuePair p.relpath {
        enable = mkDefault ((any (g: elem g p.groups) config.source.includeGroups) || (!(any (g: elem g p.groups) config.source.excludeGroups)));
        contents = mkDefault (projectSource p);
      }) json;

    unpackScript = (
      (concatStringsSep "\n" (map (d: optionalString d.enable ''
        mkdir -p ${d.path}
        ${pkgs.utillinux}/bin/mount --bind ${d.patchedContents} ${d.path}
      '') (attrValues config.source.dirs))) +
      (concatStringsSep "" (mapAttrsToList (name: p: optionalString config.source.dirs.${p.relpath}.enable
        ((concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            cp --reflink=auto -f ${p.relpath}/${c.src} ${c.dest}
          '') p.copyfiles) +
        (concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            ln -sf ./${c.src_rel_to_dest} ${c.dest}
          '') p.linkfiles))
      ) json)));
  };

  # Extract only files under robotnix/ (for debugging with an external AOSP build)
  config.build.debugUnpackScript = pkgs.writeText "debug-unpack.sh" (''
    rm -rf robotnix
    '' +
    (concatStringsSep "" (map (d: optionalString (d.enable && (hasPrefix "robotnix/" d.path)) ''
      mkdir -p $(dirname ${d.path})
      echo "${d.contents} -> ${d.path}"
      cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.patchedContents} ${d.path}/
    '') (attrValues config.source.dirs))) + ''
    chmod -R u+w robotnix/
  '');

  # Patch files in other sources besides robotnix/*
  config.build.debugPatchScript = pkgs.writeText "debug-patch.sh"
    (concatStringsSep "\n" (map (d: ''
      ${concatMapStringsSep "\n" (p: "patch -p1 --no-backup-if-mismatch -d ${d.path} < ${p}") d.patches}
      ${optionalString (d.postPatch != "") ''
      pushd ${d.path} >/dev/null
      ${d.postPatch}
      popd >/dev/null
      ''}
    '')
    (filter (d: d.enable && ((d.patches != []) || (d.postPatch != ""))) (attrValues config.source.dirs))));
}
