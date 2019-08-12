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
    LOCAL_MODULE_PATH := $(TARGET_OUT_ETC)/${dirOf f.target}
    LOCAL_MODULE_STEM := ${baseNameOf f.target}
    LOCAL_SRC_FILES := ${f.moduleName}

    include $(BUILD_PREBUILT)
  '') (attrValues config.etc)));
in
{
  options = {
    etc = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
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
        };

        config = {
          target = mkDefault name;
          source = mkIf (config.text != null) (
            let name' = "etc-" + baseNameOf name;
            in mkDefault (pkgs.writeText name' config.text));
          moduleName = mkDefault (replaceStrings [ "/" ] [ "_" ] name);
        };
      }));
    };
  };

  config = {
    source.dirs."nixdroid/etcfiles".contents = (pkgs.runCommand "nixdroid-etcfiles" {} (''
      mkdir -p $out
      cp ${androidmk} $out/Android.mk
    '' + (concatMapStringsSep "\n" (f: "cp ${f.source} $out/${f.moduleName}") (attrValues config.etc))));

    additionalProductPackages = map (f: f.moduleName) (attrValues config.etc);
  };
}
