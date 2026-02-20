# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# TODO: remove all the redfin exceptions

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    mkOptionDefault
    mkMerge
    mkEnableOption
    types
    ;

  cfg = config.kernel;
in
{
  options = {
    kernel = {
      enable = mkEnableOption "building custom kernel";

      name = mkOption {
        internal = true;
        type = types.str;
      };

      src = mkOption {
        type = types.path;
        description = "Path to kernel source";
      };

      buildDateTime = mkOption {
        type = types.int;
        description = "Unix time to use for kernel build timestamp";
        default = config.buildDateTime;
        defaultText = "config.buildDateTime";
      };

      patches = mkOption {
        default = [ ];
        type = types.listOf types.path;
        description = "List of patches to apply to kernel source";
      };

      postPatch = mkOption {
        default = "";
        type = types.lines;
        description = "Commands to run after patching kernel source";
      };

      relpath = mkOption {
        type = types.str;
        description = "Relative path in source tree to place kernel build artifacts";
      };

      clangVersion = mkOption {
        type = types.str;
        description = ''
          Version of prebuilt clang to use for kernel.
          See https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/master/README.md"
        '';
      };
    };
  };

  config = {
    # We have to replace files here, instead of just using the
    # config.build.kernel drv output in place of source.dirs.${cfg.relpath}.
    # This is because there are some additional things in the prebuilt kernel
    # output directory like kernel headers for sunfish under device/google/sunfish-kernel/sm7150
    source = mkIf cfg.enable {
      dirs.${cfg.relpath}.postPatch = ''
        # Warn if we have prebuilt files that we aren't replacing
        for filename in *; do
          if [[ -f "$filename" && ! -f "${config.build.kernel}/$filename" ]]; then
            echo "WARNING: Not replacing $filename"
          fi
        done

        cp -f ${config.build.kernel}/* .
      '';
    };
  };
}
