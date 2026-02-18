# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkOption mkDefault types;

  cfg = config.apps.prebuilt;
  androidmk =
    prebuilt:
    pkgs.writeText "Android.mk" (''
      LOCAL_PATH := $(call my-dir)

      include $(CLEAR_VARS)

      LOCAL_MODULE := ${prebuilt.moduleName}
      LOCAL_MODULE_CLASS := APPS
      LOCAL_SRC_FILES := ${prebuilt.name}.apk
      LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
      LOCAL_MODULE_TAGS := optional

      LOCAL_PRIVILEGED_MODULE := ${lib.boolToString prebuilt.privileged}
      LOCAL_CERTIFICATE := ${
        if (prebuilt.certificate == "PRESIGNED") then
          "PRESIGNED"
        else
          (if (prebuilt.certificate == "releasekey") then "testkey" else prebuilt.certificate)
      }
      ${lib.optionalString (prebuilt.partition == "vendor") "LOCAL_VENDOR_MODULE := true"}
      ${lib.optionalString (prebuilt.partition == "product") "LOCAL_PRODUCT_MODULE := true"}
      ${lib.optionalString (
        config.androidVersion >= 11 && prebuilt.usesLibraries != [ ]
      ) "LOCAL_USES_LIBRARIES := ${builtins.concatStringsSep " " prebuilt.usesLibraries}"}
      ${lib.optionalString (config.androidVersion >= 11 && prebuilt.usesOptionalLibraries != [ ])
        "LOCAL_OPTIONAL_USES_LIBRARIES := ${builtins.concatStringsSep " " prebuilt.usesOptionalLibraries}"
      }
      ${prebuilt.extraConfig}

      include $(BUILD_PREBUILT)
    '');

  enabledPrebuilts = lib.filter (p: p.enable) (lib.attrValues cfg);
in
{
  options = {
    apps.prebuilt = mkOption {
      default = { };
      description = "Prebuilt APKs to include in the robotnix build";

      type =
        let
          _config = config;
        in
        types.attrsOf (
          types.submodule (
            { name, config, ... }:
            {
              options = {
                enable = mkOption {
                  default = true;
                  description = "Include ${name} APK in Android build";
                  type = types.bool;
                };

                name = mkOption {
                  default = name;
                  description = "Name of application. (No spaces)";
                  type = types.str; # TODO: Use strMatching to enforce no spaces?
                };

                modulePrefix = mkOption {
                  default = "Robotnix";
                  description = "Prefix to prepend to the module name to avoid conflicts. (No spaces)";
                  type = types.str; # TODO: Use strMatching to enforce no spaces?
                };

                moduleName = mkOption {
                  default = "${config.modulePrefix}${config.name}";
                  description = "Module name in the AOSP build system. (No spaces)";
                  type = types.str;
                  internal = true;
                };

                apk = mkOption {
                  type = with types; nullOr path;
                  default = null; # TODO: Consider a .enable option
                  description = "APK file to include in build";
                };

                signedApk = mkOption {
                  type = types.path;
                  internal = true;
                  description = "Robotnix-signed version of APK file";
                };

                packageName = mkOption {
                  # Only used with privapp permissions
                  description = "APK's Java-style package name (applicationId). This setting only necessary to be set if also using `privappPermissions`.";
                  type = types.strMatching "[a-zA-Z0-9_.]*";
                  example = "com.android.test";
                };

                certificate = mkOption {
                  default = lib.toLower name;
                  type = types.str;
                  description = ''
                    Name of certificate to sign APK with.  Defaults to the name of the prebuilt app.
                    If it is a device-specific certificate, the cert/key should be in your keys dir under `''${device}/''${certificate}.{x509.pem,pk8}`.
                    The special string "PRESIGNED" will just use the APK as-is and not replace the signature.
                  '';
                };

                snakeoilKeyPath = mkOption {
                  type = types.path;
                  internal = true;
                };

                privileged = mkOption {
                  default = false;
                  type = types.bool;
                  description = "Whether this APK should be included as a privileged application.";
                };

                privappPermissions = mkOption {
                  default = [ ];
                  type = types.listOf types.str;
                  description = ''
                    Privileged permissions to apply to this application.
                    Refer to this [link](https://developer.android.com/reference/android/Manifest.permission) and note permissions which say
                    "not for use by third-party applications".
                  '';
                  example = [ "INSTALL_PACKAGES" ];
                };

                defaultPermissions = mkOption {
                  default = [ ];
                  type = types.listOf types.str;
                  description = "Permissions to be enabled by default without user prompting.";
                  example = [ "INSTALL_PACKAGES" ];
                };

                partition = mkOption {
                  description = "Partition on which to place this app";
                  type = types.enum [
                    "vendor"
                    "system"
                    "product"
                  ];
                };

                allowInPowerSave = mkOption {
                  default = false;
                  type = types.bool;
                  description = ''
                    Whether to allow this application to operate in \"power save\" mode.
                    Disables battery optimization for this app.
                  '';
                };

                usesLibraries = mkOption {
                  default = [ ];
                  type = types.listOf types.str;
                  description = ''
                    Shared library dependencies of this app.

                    For more information, see <https://android.googlesource.com/platform/build/+/75342c19323fea64dbc93fdc5a7def3f81113c83/Changes.md>.
                  '';
                };

                usesOptionalLibraries = mkOption {
                  default = [ ];
                  type = types.listOf types.str;
                  description = ''
                    Optional shared library dependencies of this app.

                    For more information, see <https://android.googlesource.com/platform/build/+/75342c19323fea64dbc93fdc5a7def3f81113c83/Changes.md>.
                  '';
                };

                extraConfig = mkOption {
                  default = "";
                  type = types.lines;
                  internal = true;
                };
              };

              config = {
                partition = mkDefault (if (_config.androidVersion >= 10) then "product" else "system");
              };
            }
          )
        );
    };
  };

  config = {
    source.dirs = lib.listToAttrs (
      map (prebuilt: {
        name = "robotnix/prebuilt/${prebuilt.name}";
        value = {
          src = pkgs.runCommand "prebuilt_${prebuilt.name}" { } ''
            set -euo pipefail

            mkdir -p $out
            cp ${androidmk prebuilt} $out/Android.mk
            cp ${prebuilt.apk} $out/${prebuilt.name}.apk

            ### Check minSdkVersion, targetSdkVersion
            # TODO: Also check permissions?
            MANIFEST_DUMP=$(${pkgs.robotnix.build-tools}/aapt2 d xmltree --file AndroidManifest.xml ${prebuilt.apk})

            # It would be better if we could convert it back into true XML and then select based on XPath
            MIN_SDK_VERSION=$(echo "$MANIFEST_DUMP" | grep minSdkVersion | cut -d= -f2)
            TARGET_SDK_VERSION=$(echo "$MANIFEST_DUMP" | grep targetSdkVersion | cut -d= -f2)

            if [[ "$MIN_SDK_VERSION" -gt "${builtins.toString config.apiLevel}" ]]; then
              echo "ERROR: OS API level is (${builtins.toString config.apiLevel}) but APK requires at least $MIN_SDK_VERSION"
              exit 1
            fi

            if [[ "$TARGET_SDK_VERSION" -lt "${builtins.toString config.apiLevel}" ]]; then
              echo "WARNING: APK was compiled against an older SDK API level ($TARGET_SDK_VERSION) than used in OS (${builtins.toString config.apiLevel})"
            fi
          '';
        };
      }) enabledPrebuilts
    );

    # TODO: Make just a single file with each of these configuration types instead of one for each app?
    etc =
      let
        confToAttrs =
          f:
          (lib.listToAttrs (
            map (prebuilt: {
              name = (f prebuilt).path;
              value = {
                text = (f prebuilt).text;
                inherit (prebuilt) partition;
              };
            }) (lib.filter (prebuilt: (f prebuilt).filter) enabledPrebuilts)
          ));
      in
      confToAttrs (prebuilt: {
        path = "permissions/privapp-permissions-${prebuilt.packageName}.xml";
        filter = prebuilt.privappPermissions != [ ];
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <permissions>
            <privapp-permissions package="${prebuilt.packageName}">
              ${lib.concatMapStrings (
                p: "<permission name=\"android.permission.${p}\"/>"
              ) prebuilt.privappPermissions}
            </privapp-permissions>
          </permissions>
        '';
      })
      // confToAttrs (prebuilt: {
        path = "default-permissions/default-permissions-${prebuilt.packageName}.xml";
        filter = prebuilt.defaultPermissions != [ ];
        # TODO: Allow user to set "fixed" in the configuration?
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <exceptions>
            <exception package="${prebuilt.packageName}">
              ${lib.concatMapStrings (
                p: "<permission name=\"android.permission.${p}\" fixed=\"false\"/>"
              ) prebuilt.defaultPermissions}
            </exception>
          </exceptions>
        '';
      })
      // confToAttrs (prebuilt: {
        path = "sysconfig/whitelist-${prebuilt.packageName}.xml";
        filter = prebuilt.allowInPowerSave;
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <config>
            <allow-in-power-save package="${prebuilt.packageName}"/>
          </config>
        '';
      });

    system.additionalProductPackages = map (p: p.moduleName) (
      lib.filter (p: p.partition == "system") enabledPrebuilts
    );
    product.additionalProductPackages = map (p: p.moduleName) (
      lib.filter (p: p.partition == "product") enabledPrebuilts
    );

    # Convenience derivation to get all prebuilt apks -- for use in custom fdroid repo?
    build.prebuiltApks = pkgs.linkFarm "${config.device}-prebuilt-apks" (
      map (p: {
        name = "${p.name}.apk";
        path = p.signedApk;
      }) (lib.filter (p: p.name != "CustomWebview") enabledPrebuilts)
    );
  };
}
