{ config, pkgs, lib, ... }:

with lib;
let
  repo2nix = import ./repo2nix.nix;
  json = importJSON config.source.jsonFile; # Get project source from JSON description

  projectSource = p:
    let
      ref = if strings.hasInfix "refs/heads" p.revisionExpr then last (splitString "/" p.revisionExpr) else p.revisionExpr;
      name = builtins.replaceStrings ["/"] ["="] p.relpath;
      zeroHash = "0000000000000000000000000000000000000000000000000000000000000000";
      # Try to get the sha256 by looking first for the treehash, falling back to the revision
      sha256 = lib.attrByPath [ (if (p ? tree) then p.tree else p.rev) ] zeroHash config.source.hashes;
    in
    if ((sha256 == zeroHash) && config.source.fetchGitFallback)
    then
      builtins.fetchGit { # Evaluation-time source fetching. Uses nix's git cache, but any nix-instantiate will require fetching sources.
        inherit (p) url rev;
        inherit ref name;
      }
    else
      pkgs.fetchgit { # Build-time source fetching. This should be preferred, but is slightly less convenient when developing.
        inherit (p) url rev;
        inherit sha256;
        # Submodules are manually specified as "nested projects". No support for that in repo2nix. See https://gerrit.googlesource.com/git-repo/+/master/docs/manifest-format.md
        fetchSubmodules = false;
        deepClone = false;
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

      fetchGitFallback = mkOption {
        default = false;
        description = "Allows use of builtins.fetchGit instead of pkgs.fetchgit if not all sha256 hashes are available. (Useful for development)";
      };

      jsonFile = mkOption {
        default = json;
        internal = true;
      };

      hashes = mkOption {
        type = types.attrsOf types.str;
        default = {};
        internal = true;
        description = "schema is {url: {revision: sha256}}";
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

      buildNumber = mkOption {
        default = "12345";
        type = types.str;
        description = "Build number associated with this upstream source code (just used to select images elsewhere)";
      };
    };
  };

  config.source = mkMerge [{
    jsonFile = repo2nix {
      manifest = config.source.manifest.url;
      inherit (config.source.manifest) rev sha256 localManifests;
      extraFlags = "--no-repo-verify";
      withTreeHashes = true;
    };

    dirs = mapAttrs' (name: p:
      nameValuePair p.relpath {
        enable = mkDefault ((any (g: elem g p.groups) config.source.includeGroups) || (!(any (g: elem g p.groups) config.source.excludeGroups)));
        contents = mkDefault (projectSource p);
      }) json;

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
            cp --reflink=auto -f ${p.relpath}/${c.src} ${c.dest}
          '') p.copyfiles) +
        (concatMapStringsSep "\n" (c: ''
            mkdir -p $(dirname ${c.dest})
            ln -sf ./${c.src_rel_to_dest} ${c.dest}
          '') p.linkfiles))
      ) json)));
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
          ${pkgs.bindfs}/bin/bindfs --multithreaded --perms=u+w bind-mounts src
          export sourceRoot=$PWD/src
        fi
      '';
    }
  ];

  # Extract only files under nixdroid/ (for debugging with an external AOSP build)
  config.build.debugUnpackScript = pkgs.writeText "debug-unpack.sh" (''
    rm -rf nixdroid
    '' +
    (concatStringsSep "" (map (d: optionalString (d.enable && (hasPrefix "nixdroid/" d.path)) ''
      mkdir -p $(dirname ${d.path})
      echo "${d.contents} -> ${d.path}"
      cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.patchedContents} ${d.path}/
    '') (attrValues config.source.dirs))) + ''
    chmod -R u+w nixdroid/
  '');

  # Patch files in other sources besides nixdroid/*
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
