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

  signApk = {name, apk, keyPath}: pkgs.runCommand "${name}-signed.apk" { nativeBuildInputs = [ pkgs.jre ]; } ''
    cp ${apk} $out
    ${head pkgs.androidenv.androidPkgs_9_0.build-tools}/libexec/android-sdk/build-tools/28.0.3/apksigner sign \
      --key ${keyPath}.pk8 --cert ${keyPath}.x509.pem $out
  '';

  deviceCertificates = [ "release" "platform" "media" "shared" ]; # Cert names used by AOSP
in
{
  options = {
    apps.prebuilt = mkOption {
      default = {};
      type = let
        _config = config;
      in types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          name = mkOption {
            default = name;
            type = types.str; # No spaces (use strMatching?)
          };

          apk = mkOption {
            type = types.path;
          };

          signedApk = mkOption {
            type = types.path;
            internal = true;
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

        config = {
          # Uses the sandbox exception in /keys
          signedApk = mkDefault (
            if config.certificate == "PRESIGNED" then config.apk else (signApk {
              inherit (config) name apk;
              keyPath = _config.build.sandboxKeyPath config.certificate;
            }));
        };
      }));
    };
  };

  config = {
    source.dirs = listToAttrs (map (prebuilt: {
      name = "nixdroid/prebuilt/${prebuilt.name}";
      value = {
        contents = let
          # Don't use the signed version if it's an apk that is going to get signed when signing target-files.
          apk = if builtins.elem prebuilt.certificate deviceCertificates
                then prebuilt.apk
                else prebuilt.signedApk;
        in pkgs.runCommand "prebuilt_${prebuilt.name}" {} ''
          mkdir -p $out
          cp ${androidmk prebuilt} $out/Android.mk
          cp ${apk} $out/${prebuilt.name}.apk
        '';
      };
    }) (attrValues cfg));

    etc = listToAttrs (map (prebuilt: {
        name = "permissions/${prebuilt.packageName}.xml";
        value = { text = privapp-permissions prebuilt; };
      }) (filter (prebuilt: prebuilt.privappPermissions != []) (attrValues cfg)));

    additionalProductPackages = map (prebuilt: prebuilt.name) (attrValues cfg);

    # Convenience derivation to get all prebuilt apks -- for use in custom fdroid repo?
    build.prebuiltApks = pkgs.linkFarm "${config.device}-prebuilt-apks"
      (map (p: { name="${p.name}.apk"; path=p.signedApk; })
      (filter (p: p.name != "CustomWebview") (attrValues cfg)));
  };
}
