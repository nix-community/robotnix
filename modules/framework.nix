{ config, pkgs, lib, ... }:

# TODO: Unify with "etc" and/or "apps.prebuilt" options
with lib;
let
  androidmk = pkgs.writeText "Android.mk" (''
    LOCAL_PATH := $(call my-dir)

  '' + (concatMapStringsSep "\n" (f: ''
    include $(CLEAR_VARS)

    LOCAL_MODULE := ${f.moduleName}
    LOCAL_MODULE_TAGS := optional
    LOCAL_MODULE_PATH := $(TARGET_OUT${optionalString (f.partition == "product") "_PRODUCT"})/framework/${dirOf f.target}
    LOCAL_MODULE_CLASS := JAVA_LIBRARIES
    LOCAL_SRC_FILES := ${f.moduleName}

    include $(BUILD_PREBUILT)
  '') (attrValues config.framework)));
in
{
  options = {
    framework = mkOption {
      default = {};
      internal = true; # TODO: Expose to user after cleaning up

      type = let
        _config = config;
      in types.attrsOf (types.submodule ({ name, config, ... }: {
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
            type = types.strMatching "(vendor|system|product)";
            internal = true;
          };
        };

        config = {
          target = mkDefault name;
          moduleName = mkDefault (replaceStrings [ "/" ] [ "_" ] name);
          partition = mkDefault (if (_config.androidVersion >= 10) then "product" else "system");
        };
      }));
    };
  };

  config = {
    source.dirs."robotnix/framework".src = (pkgs.runCommand "robotnix-framework" {} (''
      mkdir -p $out
      cp ${androidmk} $out/Android.mk
    '' + (concatMapStringsSep "\n" (f: "cp ${f.source} $out/${f.moduleName}") (attrValues config.framework))));

    system.additionalProductPackages = map (f: f.moduleName) (filter (f: f.partition == "system") (attrValues config.framework));
    product.additionalProductPackages = map (f: f.moduleName) (filter (f: f.partition == "product") (attrValues config.framework));
  };
}
