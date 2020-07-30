{ config, pkgs, lib, ... }:

with lib;
let
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
        description = "Include this directory in the android build source tree";
      };

      relpath = mkOption {
        default = name;
        type = types.str;
      };

      src = mkOption {
        type = types.path;
        apply = src: # Maybe replace with with pkgs.applyPatches? Need patchFlags though...
          if (config.patches != [] || config.postPatch != "")
          then (pkgs.runCommand "${builtins.replaceStrings ["/"] ["="] config.relpath}-patched" {} ''
            cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${src} $out/
            chmod u+w -R $out
            ${concatMapStringsSep "\n" (p: "patch -p1 --no-backup-if-mismatch -d $out < ${p}") config.patches}
            cd $out
            ${config.postPatch}
          '')
          else src;
      };

      patches = mkOption {
        default = [];
        type = types.listOf types.path;
      };

      postPatch = mkOption {
        default = "";
        type = types.lines;
      };

      unpackScript = mkOption {
        type = types.str;
        internal = true;
      };

      # These remaining options should be set by json output of mk-vendor-file.py
      url = mkOption {
        type = types.str;
        internal = true;
      };

      rev = mkOption {
        type = types.str;
        internal = true;
      };

      revisionExpr = mkOption {
        type = types.str;
        internal = true;
      };

      tree = mkOption {
        type = types.str;
        internal = true;
      };

      groups = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
      };

      sha256 = mkOption {
        type = types.str;
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
        (any (g: elem g config.groups) _config.source.includeGroups)
        || (!(any (g: elem g config.groups) _config.source.excludeGroups))
      );

      src = mkDefault (projectSource config);

      unpackScript = (optionalString config.enable ''
        mkdir -p ${config.relpath}
        ${pkgs.utillinux}/bin/mount --bind ${config.src} ${config.relpath}
      '')
      + (concatMapStringsSep "\n" (c: ''
        mkdir -p $(dirname ${c.dest})
        cp --reflink=auto -f ${config.relpath}/${c.src} ${c.dest}
      '') config.copyfiles)
      + (concatMapStringsSep "\n" (c: ''
        mkdir -p $(dirname ${c.dest})
        ln -sf --relative ${config.relpath}/${c.src} ${c.dest}
      '') config.linkfiles);
    };
  });
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

      dirs = mkOption {
        default = {};
        type = types.attrsOf dirModule;
      };

      excludeGroups = mkOption {
        default = [ "darwin" "mips" "hikey" ];
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
    dirs = mkIf config.source.evalTimeFetching (import ./repo2nix.nix {
      manifest = config.source.manifest.url;
      inherit (config.source.manifest) rev sha256 localManifests;
    });

    unpackScript = concatMapStringsSep "\n" (d: d.unpackScript) (attrValues config.source.dirs);
  };

  config.build = {
    unpackScript = pkgs.writeShellScript "unpack.sh" config.source.unpackScript;

    # Extract only files under robotnix/ (for debugging with an external AOSP build)
    debugUnpackScript = pkgs.writeShellScript "debug-unpack.sh" (''
      rm -rf robotnix
      '' +
      (concatStringsSep "" (map (d: optionalString (d.enable && (hasPrefix "robotnix/" d.relpath)) ''
        mkdir -p $(dirname ${d.relpath})
        echo "${d.src} -> ${d.relpath}"
        cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${d.src} ${d.relpath}/
      '') (attrValues config.source.dirs))) + ''
      chmod -R u+w robotnix/
    '');

    # Patch files in other sources besides robotnix/*
    debugPatchScript = pkgs.writeShellScript "debug-patch.sh"
      (concatStringsSep "\n" (map (d: ''
        ${concatMapStringsSep "\n" (p: "patch -p1 --no-backup-if-mismatch -d ${d.relpath} < ${p}") d.patches}
        ${optionalString (d.postPatch != "") ''
        pushd ${d.relpath} >/dev/null
        ${d.postPatch}
        popd >/dev/null
        ''}
      '')
      (filter (d: d.enable && ((d.patches != []) || (d.postPatch != ""))) (attrValues config.source.dirs))));
  };
}
