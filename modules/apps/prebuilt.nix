{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.prebuilt;
  privapp-permissions = prebuilt: ''
    <?xml version="1.0" encoding="utf-8"?>
    <permissions>
      <privapp-permissions package="${prebuilt.packageName}">
        ${concatMapStrings (p: "<permission name=\"android.permission.${p}\"/>") prebuilt.privappPermissions}
      </privapp-permissions>
    </permissions>
  '';
  androidmk = prebuilt: pkgs.writeText "Android.mk" (''
    LOCAL_PATH := $(call my-dir)

    include $(CLEAR_VARS)

    LOCAL_MODULE := ${prebuilt.name}
    LOCAL_MODULE_CLASS := APPS
    LOCAL_SRC_FILES := ${prebuilt.name}.apk
    LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
    LOCAL_MODULE_TAGS := optional

    LOCAL_PRIVILEGED_MODULE := ${if prebuilt.privileged then "true" else "false"}
    LOCAL_CERTIFICATE := ${prebuilt.certificate}
    ${prebuilt.extraConfig}

    include $(BUILD_PREBUILT)
    '');
in
{
  options = {
    apps.prebuilt = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          name = mkOption {
            default = name;
            type = types.str; # No spaces (use strMatching?)
          };

          apk = mkOption {
            type = types.path;
          };

          packageName = mkOption { # Only used with privapp permissions
            type = types.str;
            description = "example: com.android.test";
          };

          certificate = mkOption {
            default = "platform";
            type = types.str; # platform|PRESIGNED| ...
          };

          privileged = mkOption {
            default = false;
            type = types.bool;
          };

          privappPermissions = mkOption {
            default = [];
            type = types.listOf types.str;
            description = ''
              See https://developer.android.com/reference/android/Manifest.permission and note perimssions which say
              "not for use by third-party applications".
            '';
            example = ''[ "INSTALL_PACKAGES" ]'';
          };

          extraConfig = mkOption {
            default = "";
            type = types.lines;
          };
        };
      }));
    };
  };

  config = {
    source.dirs = listToAttrs (map (prebuilt: {
      name = "nixdroid/external/${prebuilt.name}";
      value = {
        contents = pkgs.runCommand "external_${prebuilt.name}" {} ''
          mkdir -p $out
          cp ${androidmk prebuilt} $out/Android.mk
          cp ${prebuilt.apk} $out/${prebuilt.name}.apk
        '';
      };
    }) (attrValues cfg));

    etc = listToAttrs (map (prebuilt: {
        name = "permissions/${prebuilt.packageName}.xml";
        value = { text = privapp-permissions prebuilt; };
      }) (filter (prebuilt: prebuilt.privappPermissions != []) (attrValues cfg)));

    additionalProductPackages = map (prebuilt: prebuilt.name) (attrValues cfg);
  };
}
