{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.prebuilt;
  androidmk = prebuilt: pkgs.writeText "Android.mk" (''
    LOCAL_PATH := $(call my-dir)

    include $(CLEAR_VARS)

    LOCAL_MODULE := ${prebuilt.name}
    LOCAL_MODULE_CLASS := APPS
    LOCAL_SRC_FILES := ${prebuilt.name}.apk
    LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
    LOCAL_MODULE_TAGS := optional

    LOCAL_PRIVILEGED_MODULE := ${if prebuilt.privileged then "true" else "false"}
    LOCAL_CERTIFICATE := ${if builtins.elem prebuilt.certificate deviceCertificates
      then (if (prebuilt.certificate == "releasekey") then "testkey" else prebuilt.certificate)
      else "PRESIGNED"
    }
    ${optionalString (prebuilt.partition == "vendor") "LOCAL_VENDOR_MODULE := true"}
    ${optionalString (prebuilt.partition == "product") "LOCAL_PRODUCT_MODULE := true"}
    ${prebuilt.extraConfig}

    include $(BUILD_PREBUILT)
    '');

  signApk = {name, apk, keyPath}: pkgs.runCommand "${name}-signed.apk" { nativeBuildInputs = [ pkgs.jre ]; } ''
    cp ${apk} $out
    ${pkgs.androidPkgs.sdk (p: with p.stable; [ tools build-tools-29-0-2 ])}/share/android-sdk/build-tools/29.0.2/apksigner sign \
      --key ${keyPath}.pk8 --cert ${keyPath}.x509.pem $out
  '';

  # Cert names used by AOSP. Only some of these make sense to be used to sign packages
  deviceCertificates = [ "releasekey" "platform" "media" "shared" "verity" ];
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
            default = "releasekey";
            type = types.str;
            description = ''
              Certificate name to sign apk with.  If it is a device certificate, the cert/key will be ''${keyStorePath}/''${device}/''${certificate}.{x509.pem,pk8}
              Otherwise, it will be ''${keyStorePath}/''${certificate}.{x509.pem,pk8}
              Finally, the special string "PRESIGNED" will just use the apk as-is.
            '';
          };

          privileged = mkOption {
            default = false;
            type = types.bool;
          };

          privappPermissions = mkOption {
            default = [];
            type = types.listOf types.str;
            description = ''
              See https://developer.android.com/reference/android/Manifest.permission and note permissions which say
              "not for use by third-party applications".
            '';
            example = ''[ "INSTALL_PACKAGES" ]'';
          };

          defaultPermissions = mkOption {
            default = [];
            type = types.listOf types.str;
            description = ''
              Permissions which are to be enabled by default without user prompting
            '';
            example = ''[ "INSTALL_PACKAGES" ]'';
          };

          partition = mkOption {
            type = types.strMatching "(vendor|system|product)";
          };

          allowInPowerSave = mkOption {
            default = false;
            type = types.bool;
          };

          extraConfig = mkOption {
            default = "";
            type = types.lines;
          };
        };

        config = {
          partition = mkDefault (if (_config.androidVersion >= 10) then "product" else "system");

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
      name = "robotnix/prebuilt/${prebuilt.name}";
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

    # TODO: Make just a single file with each of these tconfiguration types instead of one for each app?
    etc = let
      confToAttrs = f:
        (listToAttrs (map (prebuilt: {
          name = (f prebuilt).path;
          value = {
            text = (f prebuilt).text;
            inherit (prebuilt) partition;
          };
        }) (filter (prebuilt: (f prebuilt).filter) (attrValues cfg))));
    in
      confToAttrs (prebuilt: {
        path = "permissions/privapp-permissions-${prebuilt.packageName}.xml";
        filter = prebuilt.privappPermissions != [];
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <permissions>
            <privapp-permissions package="${prebuilt.packageName}">
              ${concatMapStrings (p: "<permission name=\"android.permission.${p}\"/>") prebuilt.privappPermissions}
            </privapp-permissions>
          </permissions>
        '';
      }) //
      confToAttrs (prebuilt: {
        path = "default-permissions/default-permissions-${prebuilt.packageName}.xml";
        filter = prebuilt.defaultPermissions != [];
        # TODO: Allow user to set "fixed" in the configuration?
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <exceptions>
            <exception package="${prebuilt.packageName}">
              ${concatMapStrings (p: "<permission name=\"android.permission.${p}\" fixed=\"false\"/>") prebuilt.defaultPermissions}
            </exception>
          </exceptions>
        '';
      }) //
      confToAttrs (prebuilt: {
        path = "sysconfig/whitelist-${prebuilt.packageName}.xml";
        filter = prebuilt.allowInPowerSave;
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <config>
            <allow-in-power-save package="${prebuilt.packageName}"/>
          </config>
        '';
      });

    system.additionalProductPackages = map (p: p.name) (filter (p: p.partition == "system") (attrValues cfg));
    product.additionalProductPackages = map (p: p.name) (filter (p: p.partition == "product") (attrValues cfg));

    # Convenience derivation to get all prebuilt apks -- for use in custom fdroid repo?
    build.prebuiltApks = pkgs.linkFarm "${config.device}-prebuilt-apks"
      (map (p: { name="${p.name}.apk"; path=p.signedApk; })
      (filter (p: p.name != "CustomWebview") (attrValues cfg)));
  };
}
