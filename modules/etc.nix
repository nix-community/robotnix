# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

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
    mkDefault
    mkMerge
    mkEnableOption
    types
    ;

  androidmk = pkgs.writeText "Android.mk" (
    ''
      LOCAL_PATH := $(call my-dir)

    ''
    + (lib.concatMapStringsSep "\n" (f: ''
      include $(CLEAR_VARS)

      LOCAL_MODULE := ${f.moduleName}
      LOCAL_MODULE_TAGS := optional
      LOCAL_MODULE_CLASS := ETC
      LOCAL_MODULE_PATH := $(TARGET_OUT${
        lib.optionalString (f.partition == "product") "_PRODUCT"
      })/etc/${dirOf f.target}
      LOCAL_MODULE_STEM := ${baseNameOf f.target}
      LOCAL_SRC_FILES := ${f.moduleName}

      include $(BUILD_PREBUILT)
    '') (lib.attrValues config.etc))
  );
in
{
  options = {
    etc = mkOption {
      default = { };
      description = "Set of files to be included under `/etc`";

      type =
        let
          _config = config;
        in
        types.attrsOf (
          types.submodule (
            { name, config, ... }:
            {
              # robotnix etc.* options correspond to the etc.* options from NixOS
              options = {
                target = mkOption {
                  type = types.str;
                  description = "Name of symlink (relative to `/etc`). Defaults to the attribute name.";
                };

                text = mkOption {
                  default = null;
                  type = types.nullOr types.str;
                  description = "Text of the file";
                };

                source = mkOption {
                  type = types.path;
                  description = "Path of the source file";
                };

                moduleName = mkOption {
                  type = types.str;
                  internal = true;
                };

                partition = mkOption {
                  type = types.enum [
                    "vendor"
                    "system"
                    "product"
                  ];
                  description = "Partition on which to place this etc file";
                };
              };

              config = {
                target = mkDefault name;
                source = mkIf (config.text != null) (
                  let
                    name' = "etc-" + baseNameOf name;
                  in
                  mkDefault (pkgs.writeText name' config.text)
                );
                moduleName = mkDefault (lib.replaceStrings [ "/" ] [ "_" ] name);
                partition = mkDefault (if (_config.androidVersion >= 10) then "product" else "system");
              };
            }
          )
        );
    };
  };

  config = {
    source.dirs."robotnix/etcfiles".src = (
      pkgs.runCommand "robotnix-etcfiles" { } (
        ''
          mkdir -p $out
          cp ${androidmk} $out/Android.mk
        ''
        + (lib.concatMapStringsSep "\n" (f: "cp ${f.source} $out/${f.moduleName}") (
          lib.attrValues config.etc
        ))
      )
    );

    system.additionalProductPackages = map (f: f.moduleName) (
      lib.filter (f: f.partition == "system") (lib.attrValues config.etc)
    );
    product.additionalProductPackages = map (f: f.moduleName) (
      lib.filter (f: f.partition == "product") (lib.attrValues config.etc)
    );
  };
}
