# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkDefault mkMerge mkOption types;

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

      manifestSrc = mkOption {
        type = types.nullOr types.path;
        description = "The original directory source as specified in the repo manifest lockfile.";
        internal = true;
        default = null;
      };

      src = mkOption {
        type = types.path;
        description = "Source to use for this android source directory.";
        default = pkgs.runCommand "empty" {} "mkdir -p $out";
        apply = src: # Maybe replace with with pkgs.applyPatches? Need patchFlags though...
          if (config.patches != [] || config.postPatch != "")
          then (pkgs.runCommand "${builtins.replaceStrings ["/"] ["="] config.relpath}-patched" { inherit (config) nativeBuildInputs; } ''
            cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${src} $out/
            chmod u+w -R $out
            ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && patch -p1 --no-backup-if-mismatch -d $out < ${p}") config.patches}
            ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && ${pkgs.git}/bin/git apply --directory=$out --unsafe-paths ${p}") config.gitPatches}
            cd $out
            ${config.postPatch}
          '')
          else src;
      };

      rev = mkOption {
        type = types.nullOr types.str;
        description = "The git commit hash of the source as specified in the repo manifest lockfile.";
        internal = true;
        default = null;
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

      nativeBuildInputs = mkOption {
        default = [];
        type = types.listOf types.package;
        description = "nativeBuildInputs to be made available during the execution of postPatch";
      };

      unpackScript = mkOption {
        type = types.str;
        internal = true;
      };

      groups = mkOption {
        type = types.listOf types.str;
        default = [];
        internal = true;
      };

      linkfiles = mkOption {
        type = types.listOf fileModule;
        default = [];
        description = ''
          Symlinks into this source dir to create in the source tree, i.e. the robotnix implementation of the git-repo `linkfile` tag.
        '';
      };

      copyfiles = mkOption {
        type = types.listOf fileModule;
        default = [];
        description  = ''
          Files to copy from this source dir elsewhere into the source tree, i.e. the robotnix implementation of the git-repo `copyfile` tag.
        '';
      };

      date = mkOption {
        type = types.nullOr types.int;
        default = null;
        internal = true;
      };
    };

    config = {
      enable = mkDefault (
        (lib.any (g: lib.elem g config.groups) _config.source.includeGroups)
        || (!(lib.any (g: lib.elem g config.groups) _config.source.excludeGroups))
      );

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
        if [[ ! -a ${c.dest} ]]; then
          ln -s --relative ${config.relpath}/${c.src} ${c.dest}
        fi
      '') config.linkfiles);

      src = lib.mkIf (config.manifestSrc != null) (lib.mkDefault config.manifestSrc);
    };
  });
in
{
  options = {
    source = {
      manifest = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to import the source dirs from a git-repo lockfile.
          '';
        };

        lockfile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            git-repo manifest lockfile as generated by `repo-tool fetch`.
          '';
        };

        categories = mkOption {
          type = types.listOf (types.either types.str (types.attrsOf types.str));
          description = ''
            `repo2nix` project categories to include from the manifest.
          '';
        };
      };

      dirs = mkOption {
        default = {};
        type = types.attrsOf dirModule;
        description = ''
          Directories to include in Android build process. Normally set by the entries of the lockfile specificed by `source.repoLockfile`, but can also be used to add additional directories.
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
    };
  };

  config.source = {
    manifest.categories = [ "Default" ];
    dirs = mkIf config.source.manifest.enable (
      let
        entries = (lib.importJSON config.source.manifest.lockfile).entries;
        filteredEntries = lib.filterAttrs (
          path: entry: entry.project.active && (builtins.any (cat: builtins.elem cat entry.project.categories) config.source.manifest.categories)
        ) entries;
        dirs = lib.mapAttrs (path: entry: {
          manifestSrc = pkgs.fetchgit {
            url = entry.project.repo_ref.repo_url;
            rev = entry.lock.commit;
            hash = entry.lock.nix_hash;
            fetchLFS = entry.project.repo_ref.fetch_lfs;
            fetchSubmodules = entry.project.repo_ref.fetch_submodules;
          };
          inherit (entry.project) groups linkfiles copyfiles;
          inherit (entry.lock) date;
          rev = entry.lock.commit;
        }) filteredEntries;
      in dirs);
  };

  config = {
    assertions = [
      {
        assertion = config.source.manifest.enable -> (lib.importJSON config.source.manifest.lockfile).fetch_completed;
        message = "The git-repo lockfile set via `source.manifest.lockfile` is marked as incomplete. Try rerunning `repo fetch` on it.";
      }
    ];
    build = {
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
  };
}
