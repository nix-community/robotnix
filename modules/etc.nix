# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

with lib;
let
  androidmk = pkgs.writeText "Android.mk" (''
    LOCAL_PATH := $(call my-dir)

  '' + (concatMapStringsSep "\n" (f: ''
    include $(CLEAR_VARS)

    LOCAL_MODULE := ${f.moduleName}
    LOCAL_MODULE_TAGS := optional
    LOCAL_MODULE_CLASS := ETC
    LOCAL_MODULE_PATH := $(TARGET_OUT${optionalString (f.partition == "product") "_PRODUCT"})/etc/${dirOf f.target}
    LOCAL_MODULE_STEM := ${baseNameOf f.target}
    LOCAL_SRC_FILES := ${f.moduleName}

    include $(BUILD_PREBUILT)
  '') (attrValues config.etc)));
in
{
  options = {
    etc = mkOption {
      default = {};
      type = let
        _config = config;
      in types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          target = mkOption {
            type = types.str;
          };

          text = mkOption {
            default = null;
            type = types.nullOr types.str;
          };

          source = mkOption {
            type = types.path;
          };

          moduleName = mkOption {
            type = types.str;
            internal = true;
          };

          partition = mkOption {
            type = types.strMatching "(vendor|system|product)";
          };
        };

        config = {
          target = mkDefault name;
          source = mkIf (config.text != null) (
            let name' = "etc-" + baseNameOf name;
            in mkDefault (pkgs.writeText name' config.text));
          moduleName = mkDefault (replaceStrings [ "/" ] [ "_" ] name);
          partition = mkDefault (if (_config.androidVersion >= 10) then "product" else "system");
        };
      }));
    };
  };

  config = {
    source.dirs."robotnix/etcfiles".src = (pkgs.runCommand "robotnix-etcfiles" {} (''
      mkdir -p $out
      cp ${androidmk} $out/Android.mk
    '' + (concatMapStringsSep "\n" (f: "cp ${f.source} $out/${f.moduleName}") (attrValues config.etc))));

    system.additionalProductPackages = map (f: f.moduleName) (filter (f: f.partition == "system") (attrValues config.etc));
    product.additionalProductPackages = map (f: f.moduleName) (filter (f: f.partition == "product") (attrValues config.etc));
  };
}
