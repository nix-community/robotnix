# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkOption mkDefault types;

  cfg = config.apps.prebuilt;
  androidmk = prebuilt: pkgs.writeText "Android.mk" (''
    LOCAL_PATH := $(call my-dir)

    include $(CLEAR_VARS)

    LOCAL_MODULE := ${prebuilt.moduleName}
    LOCAL_MODULE_CLASS := APPS
    LOCAL_SRC_FILES := ${prebuilt.name}.apk
    LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
    LOCAL_MODULE_TAGS := optional

    LOCAL_PRIVILEGED_MODULE := ${lib.boolToString prebuilt.privileged}
    LOCAL_CERTIFICATE := ${
      if (prebuilt.certificate == "PRESIGNED") then "PRESIGNED"
      else if builtins.elem prebuilt.certificate deviceCertificates
        then (if (prebuilt.certificate == "releasekey") then "testkey" else prebuilt.certificate)
      else "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}"
    }
    ${lib.optionalString (prebuilt.partition == "vendor") "LOCAL_VENDOR_MODULE := true"}
    ${lib.optionalString (prebuilt.partition == "product") "LOCAL_PRODUCT_MODULE := true"}
    ${lib.optionalString (config.androidVersion >= 11 && prebuilt.usesLibraries != []) "LOCAL_USES_LIBRARIES := ${builtins.concatStringsSep " " prebuilt.usesLibraries}"}
    ${lib.optionalString (config.androidVersion >= 11 && prebuilt.usesOptionalLibraries != []) "LOCAL_OPTIONAL_USES_LIBRARIES := ${builtins.concatStringsSep " " prebuilt.usesOptionalLibraries}"}
    ${prebuilt.extraConfig}

    include $(BUILD_PREBUILT)
    '');

  # Cert fingerprints from default AOSP test-keys: build/make/tools/releasetools/testdata
  defaultDeviceCertFingerprints = {
    "releasekey" = "A40DA80A59D170CAA950CF15C18C454D47A39B26989D8B640ECD745BA71BF5DC";
    "platform" = "C8A2E9BCCF597C2FB6DC66BEE293FC13F2FC47EC77BC6B2B0D52C11F51192AB8";
    "media" = "465983F7791F2ABEB43EA2CBDC7F21A8260B72BC08A55C839FC1A43BC741A81E";
    "shared" = "28BBFE4A7B97E74681DC55C2FBB6CCB8D6C74963733F6AF6AE74D8C3A6E879FD";
    "verity" = "8AD127ABAE8285B582EA36745F220AB8FE397FFB3B068DF19CA22D122C7B3B86";
  };
  deviceCertificates = lib.attrNames defaultDeviceCertFingerprints;

  keyPath = name:
    if builtins.elem name deviceCertificates
      then (if config.signing.enable
        then "${config.device}/${name}"
        else "${lib.replaceStrings ["releasekey"] ["testkey"] name}") # If not signing.enable, use test keys from AOSP
      else "${name}";

  putInStore = path: if (lib.hasPrefix builtins.storeDir path) then path else (/. + path);

  enabledPrebuilts = lib.filter (p: p.enable) (lib.attrValues cfg);
in
{
  options = {
    apps.prebuilt = mkOption {
      default = {};
      description = "Prebuilt APKs to include in the robotnix build";

      type = let
        _config = config;
      in types.attrsOf (types.submodule ({ name, config, ... }: {
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

          fingerprint = mkOption {
            description = "SHA256 fingerprint from certificate used to sign apk. Should be set automatically based on `keyStorePath` if `signing.enable = true`";
            type = types.strMatching "[0-9A-F]{64}"; # TODO: Type check fingerprints elsewhere
            apply = lib.toUpper;
            internal = true;
          };

          packageName = mkOption { # Only used with privapp permissions
            description = "APK's Java-style package name (applicationId). This setting only necessary to be set if also using `privappPermissions`.";
            type = types.strMatching "[a-zA-Z0-9_.]*";
            example = "com.android.test";
          };

          certificate = mkOption {
            default = lib.toLower name;
            type = types.str;
            description = ''
              Name of certificate to sign APK with.  Defaults to the name of the prebuilt app.
              If it is a device-specific certificate, the cert/key should be under `''${keyStorePath}/''${device}/''${certificate}.{x509.pem,pk8}`.
              Otherwise, it should be `''${keyStorePath}/''${certificate}.{x509.pem,pk8}`.
              Finally, the special string "PRESIGNED" will just use the APK as-is.
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
            default = [];
            type = types.listOf types.str;
            description = ''
              Privileged permissions to apply to this application.
              Refer to this [link](https://developer.android.com/reference/android/Manifest.permission) and note permissions which say
              "not for use by third-party applications".
            '';
            example = [ "INSTALL_PACKAGES" ];
          };

          defaultPermissions = mkOption {
            default = [];
            type = types.listOf types.str;
            description = "Permissions to be enabled by default without user prompting.";
            example = [ "INSTALL_PACKAGES" ];
          };

          partition = mkOption {
            description = "Partition on which to place this app";
            type = types.enum [ "vendor" "system" "product" ];
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
            default = [];
            type = types.listOf types.str;
            description = ''
              Shared library dependencies of this app.

              For more information, see <https://android.googlesource.com/platform/build/+/75342c19323fea64dbc93fdc5a7def3f81113c83/Changes.md>.
            '';
          };

          usesOptionalLibraries = mkOption {
            default = [];
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

          # Uses the sandbox exception in /keys
          signedApk = mkDefault (
            if config.certificate == "PRESIGNED" then config.apk else (pkgs.robotnix.signApk {
              inherit (config) apk;
              keyPath =
                if _config.signing.enable
                # $KEYSDIR is set by the withKeys wrapper
                then "$KEYSDIR/${keyPath config.certificate}"
                else "${config.snakeoilKeyPath}/${config.certificate}";
              keysFun = _config.build.signing.withKeys _config.signing.keyStorePath;
            }));

          fingerprint = let
            snakeoilFingerprint = pkgs.robotnix.certFingerprint (s: s) "${config.snakeoilKeyPath}/${config.certificate}.x509.pem";
          in mkDefault (
            if config.certificate == "PRESIGNED"
              then pkgs.robotnix.apkFingerprint config.signedApk # TODO: IFD
            else if _config.signing.enable
            # $KEYSDIR is set by the withKeys wrapper
            then pkgs.robotnix.certFingerprint (_config.build.signing.withKeys _config.signing.keyStorePath) "$KEYSDIR/${keyPath config.certificate}.x509.pem" # TODO: IFD
            else # !_config.signing.enable
              defaultDeviceCertFingerprints.${name} or (
                builtins.trace ''
                Used IFD to get fingerprint of reproducible app certificate.
                Recommend setting:
                apps.prebuilt.${config.name}.fingerprint = mkIf (!config.signing.enable) "${snakeoilFingerprint}"
                ''
                snakeoilFingerprint
              )
          );

          snakeoilKeyPath = pkgs.runCommand "${config.certificate}-snakeoil-cert" {} ''
            echo "Generating snakeoil key for ${config.name} (will be replaced when signing target files)"
            # Using certtool + sha256 of the cert name as seed for reproducibility. Seed needs 28 bytes for 2048 bit keys.
            ${pkgs.gnutls}/bin/certtool \
              --generate-privkey --outfile ${config.certificate}.key \
              --key-type=rsa --bits=2048 \
              --seed=${builtins.substring 0 (28*2) (builtins.hashString "sha256" config.certificate)}
            # Set serial number and fake time for reproducibility
            ${pkgs.libfaketime}/bin/faketime -f "2020-01-01 00:00:01" \
              ${pkgs.openssl}/bin/openssl req -new -x509 -sha256 \
                -key ${config.certificate}.key -out ${config.certificate}.x509.pem \
                -days 10000 -subj "/CN=Robotnix ${config.certificate}" \
                -set_serial 0
            # Convert to DER format
            ${pkgs.openssl}/bin/openssl pkcs8 -in ${config.certificate}.key -topk8 -nocrypt -outform DER -out ${config.certificate}.pk8
            mkdir -p $out/
            cp ${config.certificate}.{pk8,x509.pem} $out/
          '';
          };
      }));
    };
  };

  config = {
    source.dirs = lib.listToAttrs (map (prebuilt: {
      name = "robotnix/prebuilt/${prebuilt.name}";
      value = {
        src = pkgs.runCommand "prebuilt_${prebuilt.name}" {} (''
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
        '' + lib.optionalString ((prebuilt.certificate != "PRESIGNED") && !(builtins.elem prebuilt.certificate deviceCertificates)) ''
          cp ${prebuilt.snakeoilKeyPath}/${prebuilt.certificate}.{pk8,x509.pem} $out/
        '');
      };
    }) enabledPrebuilts);

    # TODO: Make just a single file with each of these configuration types instead of one for each app?
    etc = let
      confToAttrs = f:
        (lib.listToAttrs (map (prebuilt: {
          name = (f prebuilt).path;
          value = {
            text = (f prebuilt).text;
            inherit (prebuilt) partition;
          };
        }) (lib.filter (prebuilt: (f prebuilt).filter) enabledPrebuilts)));
    in
      confToAttrs (prebuilt: {
        path = "permissions/privapp-permissions-${prebuilt.packageName}.xml";
        filter = prebuilt.privappPermissions != [];
        text = ''
          <?xml version="1.0" encoding="utf-8"?>
          <permissions>
            <privapp-permissions package="${prebuilt.packageName}">
              ${lib.concatMapStrings (p: "<permission name=\"android.permission.${p}\"/>") prebuilt.privappPermissions}
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
              ${lib.concatMapStrings (p: "<permission name=\"android.permission.${p}\" fixed=\"false\"/>") prebuilt.defaultPermissions}
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

    system.additionalProductPackages = map (p: p.moduleName) (lib.filter (p: p.partition == "system") enabledPrebuilts);
    product.additionalProductPackages = map (p: p.moduleName) (lib.filter (p: p.partition == "product") enabledPrebuilts);

    # Convenience derivation to get all prebuilt apks -- for use in custom fdroid repo?
    build.prebuiltApks = pkgs.linkFarm "${config.device}-prebuilt-apks"
      (map (p: { name="${p.name}.apk"; path=p.signedApk; })
      (lib.filter (p: p.name != "CustomWebview") enabledPrebuilts));
  };
}
