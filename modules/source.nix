# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkDefault mkOption types;

  projectSource = p:
    let
      ref = if lib.strings.hasInfix "refs/heads" p.revisionExpr then lib.last (lib.splitString "/" p.revisionExpr) else p.revisionExpr;
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
        inherit (p) url sha256 fetchSubmodules fetchLFS;
        # Use revisionExpr if it is a tag so we use the tag in the name of the nix derivation instead of the revision
        rev = if (p.revisionExpr != null && lib.hasPrefix "refs/tags/" p.revisionExpr) then p.revisionExpr else p.rev;
        deepClone = false;
      };


  # A tree (attrset containing attrsets) which matches the source directories relpath filesystem structure.
  # e.g.
  # {
  #   "build" = {
  #     "make" = {};
  #     "soong" = {};
  #     ...
  #    }
  #    ...
  #  };
  dirsTree = let
    listToTreeBranch = xs:
      if builtins.length xs == 0 then {}
      else { "${builtins.head xs}" = listToTreeBranch (builtins.tail xs); };
    combineTreeBranches = branches:
      lib.foldr lib.recursiveUpdate {} branches;
    enabledDirs = lib.filterAttrs (name: dir: dir.enable) config.source.dirs;
  in
    combineTreeBranches (lib.mapAttrsToList (name: dir: listToTreeBranch (lib.splitString "/" dir.relpath)) enabledDirs);

  fileModule = types.submodule ({ config, ... }: {
    options = {
      src = mkOption {
        type = types.str;
        internal = true;
      };

      dest = mkOption {
        type = types.str;
        internal = true;
      };
    };
  });

  dirModule = let
    _config = config;
  in types.submodule ({ name, config, ... }: {
    options = {
      enable = mkOption {
        default = true;
        type = types.bool;
        description = "Whether to include this directory in the android build source tree.";
      };

      relpath = mkOption {
        default = name;
        type = types.str;
        description = "Relative path under android source tree to place this directory. Defaults to attribute name.";
      };

      src = mkOption {
        type = types.path;
        description = "Source to use for this android source directory.";
        default = pkgs.runCommand "empty" {} "mkdir -p $out";
        apply = src: # Maybe replace with with pkgs.applyPatches? Need patchFlags though...
          if (config.patches != [] || config.postPatch != "")
          then (pkgs.runCommand "${builtins.replaceStrings ["/"] ["="] config.relpath}-patched" {} ''
            cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${src} $out/
            chmod u+w -R $out
            ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && patch -p1 --no-backup-if-mismatch -d $out < ${p}") config.patches}
            ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && ${pkgs.git}/bin/git apply --directory=$out --unsafe-paths ${p}") config.gitPatches}
            cd $out
            ${config.postPatch}
          '')
          else src;
      };

      patches = mkOption {
        default = [];
        type = types.listOf types.path;
        description = "Patches to apply to source directory.";
      };

      # TODO: Ugly workaround since "git apply" doesn't handle fuzz in the hunk
      # line numbers like GNU patch does.
      gitPatches = mkOption {
        default = [];
        type = types.listOf types.path;
        description = "Patches to apply to source directory using 'git apply' instead of GNU patch.";
        internal = true;
      };

      postPatch = mkOption {
        default = "";
        type = types.lines;
        description = "Additional commands to run after patching source directory.";
      };

      unpackScript = mkOption {
        type = types.str;
        internal = true;
      };

      # These remaining options should be set by json output of mk-vendor-file.py
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        internal = true;
      };

      rev = mkOption {
        type = types.nullOr types.str;
        default = null;
        internal = true;
      };

      revisionExpr = mkOption {
        type = types.nullOr types.str;
        default = null;
        internal = true;
      };

      tree = mkOption {
        type = types.nullOr types.str;
        default = null;
        internal = true;
      };

      groups = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
      };

      dateTime = mkOption {
        default = 1;
        type = types.int;
        internal = true;
      };

      sha256 = mkOption {
        type = types.nullOr types.str;
        default = null;
        internal = true;
      };

      fetchSubmodules = mkOption {
        type = types.bool;
        default = false;
        internal = true;
      };

      fetchLFS = mkOption {
        type = types.bool;
        default = true;
        internal = true;
      };

      linkfiles = mkOption {
        default = [];
        type = types.listOf fileModule;
        internal = true;
      };

      copyfiles = mkOption {
        default = [];
        type = types.listOf fileModule;
        internal = true;
      };
    };

    config = {
      enable = mkDefault (
        (lib.any (g: lib.elem g config.groups) _config.source.includeGroups)
        || (!(lib.any (g: lib.elem g config.groups) _config.source.excludeGroups))
      );

      src =
        mkIf ((config.url != null) && (config.rev != null) && (config.sha256 != null))
        (mkDefault (projectSource config));

      postPatch = let
        # Check if we need to make mountpoints in this directory for other repos to be mounted inside it.
        relpathSplit = lib.splitString "/" config.relpath;
        mountPoints = lib.attrNames (lib.attrByPath relpathSplit {} dirsTree);
      in mkIf (mountPoints != [])
        ((lib.concatMapStringsSep "\n" (mountPoint: "mkdir -p ${mountPoint}") mountPoints) + "\n");

      unpackScript = (lib.optionalString config.enable ''
        mkdir -p ${config.relpath}
        ${pkgs.util-linux}/bin/mount --bind ${config.src} ${config.relpath}
      '')
      + (lib.concatMapStringsSep "\n" (c: ''
        mkdir -p $(dirname ${c.dest})
        cp --reflink=auto -f ${config.relpath}/${c.src} ${c.dest}
      '') config.copyfiles)
      + (lib.concatMapStringsSep "\n" (c: ''
        mkdir -p $(dirname ${c.dest})
        ln -sf --relative ${config.relpath}/${c.src} ${c.dest}
      '') config.linkfiles);
    };
  });
in
{
  options = {
    source = {
      # End-user should either set source.manifest.* or source.dirs
      manifest = {
        url = mkOption {
          type = types.str;
          description = "URL to repo manifest repository. Not necessary to set if using `source.dirs` directly.";
        };

        rev = mkOption {
          type = types.str;
          description = "Revision/tag to use from repo manifest repository.";
        };

        sha256 = mkOption {
          type = types.str;
          description = "Nix sha256 hash of repo manifest repository.";
        };
      };

      evalTimeFetching = mkOption {
        default = false;
        description = ''
          Set config.source.dirs automatically using IFD with information from `source.manifest`.
          Also enables use of `builtins.fetchGit` instead of `pkgs.fetchgit` if not all sha256 hashes are available.
          (Can be useful for development, but not recommended normally)
        '';
      };

      dirs = mkOption {
        default = {};
        type = types.attrsOf dirModule;
        description = ''
          Directories to include in Android build process.
          Normally set by the output of `mk_repo_file.py`.
          However, additional source directories can be added to the build here using this option as well.
        '';
      };

      excludeGroups = mkOption {
        default = [ "darwin" "mips" ];
        type = types.listOf types.str;
        description = "Project groups to exclude from source tree";
      };

      includeGroups = mkOption {
        default = [];
        type = types.listOf types.str;
        description = "Project groups to include in source tree (overrides `excludeGroups`)";
      };

      unpackScript = mkOption {
        default = "";
        internal = true;
        type = types.lines;
      };
    };
  };

  config.source = {
    dirs = mkIf config.source.evalTimeFetching (import ./repo2nix.nix {
      manifest = config.source.manifest.url;
      inherit (config.source.manifest) rev sha256;
    });

    unpackScript = lib.concatMapStringsSep "\n" (d: d.unpackScript) (lib.attrValues config.source.dirs);
  };

  config.build = {
    unpackScript = pkgs.writeShellScript "unpack.sh" config.source.unpackScript;

    # Extract only files under robotnix/ (for debugging with an external AOSP build)
    debugUnpackScript = pkgs.writeShellScript "debug-unpack.sh" (''
      rm -rf robotnix
      '' +
      (lib.concatStringsSep "" (map (d: lib.optionalString (d.enable && (lib.hasPrefix "robotnix/" d.relpath)) ''
        mkdir -p $(dirname ${d.relpath})
        echo "${d.src} -> ${d.relpath}"
        cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.src} ${d.relpath}/
      '') (lib.attrValues config.source.dirs))) + ''
      chmod -R u+w robotnix/
    '');

    # Patch files in other sources besides robotnix/*
    debugPatchScript = pkgs.writeShellScript "debug-patch.sh"
      (lib.concatStringsSep "\n" (map (d: ''
        ${lib.concatMapStringsSep "\n" (p: "patch -p1 --no-backup-if-mismatch -d ${d.relpath} < ${p}") d.patches}
        ${lib.optionalString (d.postPatch != "") ''
        pushd ${d.relpath} >/dev/null
        ${d.postPatch}
        popd >/dev/null
        ''}
      '')
      (lib.filter (d: d.enable && ((d.patches != []) || (d.postPatch != ""))) (lib.attrValues config.source.dirs))));
  };
}
