# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

# TODO: Unify with "etc" and/or "apps.prebuilt" options
let
  inherit (lib) mkOption mkDefault types;

  androidmk = pkgs.writeText "Android.mk" (
    ''
      LOCAL_PATH := $(call my-dir)

    ''
    + (lib.concatMapStringsSep "\n" (f: ''
      include $(CLEAR_VARS)

      LOCAL_MODULE := ${f.moduleName}
      LOCAL_MODULE_TAGS := optional
      LOCAL_MODULE_PATH := $(TARGET_OUT${
        lib.optionalString (f.partition == "product") "_PRODUCT"
      })/framework/${dirOf f.target}
      LOCAL_MODULE_CLASS := JAVA_LIBRARIES
      LOCAL_SRC_FILES := ${f.moduleName}

      include $(BUILD_PREBUILT)
    '') (lib.attrValues config.framework))
  );
in
{
  options = {
    framework = mkOption {
      default = { };
      internal = true; # TODO: Expose to user after cleaning up

      type =
        let
          _config = config;
        in
        types.attrsOf (
          types.submodule (
            { name, config, ... }:
            {
              options = {
                target = mkOption {
                  type = types.str;
                  internal = true;
                };

                source = mkOption {
                  type = types.path;
                  internal = true;
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
                  internal = true;
                };
              };

              config = {
                target = mkDefault name;
                moduleName = mkDefault (lib.replaceStrings [ "/" ] [ "_" ] name);
                partition = mkDefault (if (_config.androidVersion >= 10) then "product" else "system");
              };
            }
          )
        );
    };
  };

  config = {
    source.dirs."robotnix/framework".src = (
      pkgs.runCommand "robotnix-framework" { } (
        ''
          mkdir -p $out
          cp ${androidmk} $out/Android.mk
        ''
        + (lib.concatMapStringsSep "\n" (f: "cp ${f.source} $out/${f.moduleName}") (
          lib.attrValues config.framework
        ))
      )
    );

    system.additionalProductPackages = map (f: f.moduleName) (
      lib.filter (f: f.partition == "system") (lib.attrValues config.framework)
    );
    product.additionalProductPackages = map (f: f.moduleName) (
      lib.filter (f: f.partition == "product") (lib.attrValues config.framework)
    );
  };
}
