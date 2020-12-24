{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.prebuilt;
  androidmk = prebuilt: pkgs.writeText "Android.mk" (''
    LOCAL_PATH := $(call my-dir)

    include $(CLEAR_VARS)

    # Add a prefix to avoid potential conflicts with existing modules
    LOCAL_MODULE := Robotnix${prebuilt.name}
    LOCAL_MODULE_CLASS := APPS
    LOCAL_SRC_FILES := ${prebuilt.name}.apk
    LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
    LOCAL_MODULE_TAGS := optional

    LOCAL_PRIVILEGED_MODULE := ${boolToString prebuilt.privileged}
    LOCAL_CERTIFICATE := ${
      if (prebuilt.certificate == "PRESIGNED") then "PRESIGNED"
      else if builtins.elem prebuilt.certificate deviceCertificates
        then (if (prebuilt.certificate == "releasekey") then "testkey" else prebuilt.certificate)
      else "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}"
    }
    ${optionalString (prebuilt.partition == "vendor") "LOCAL_VENDOR_MODULE := true"}
    ${optionalString (prebuilt.partition == "product") "LOCAL_PRODUCT_MODULE := true"}
    ${prebuilt.extraConfig}

    include $(BUILD_PREBUILT)
    '');

  # Device-specific certificate names used by AOSP
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

          fingerprint = mkOption {
            description = "SHA256 fingerprint from certificate used to sign apk";
            type = types.strMatching "[0-9A-F]{64}"; # TODO: Type check fingerprints elsewhere
            apply = toUpper;
            internal = true;
          };

          packageName = mkOption { # Only used with privapp permissions
            type = types.str;
            description = "example: com.android.test";
          };

          certificate = mkOption {
            default = toLower name;
            type = types.str;
            description = ''
              Certificate name to sign apk with.  Defaults to the name of the prebuilt app.
              If it is a device-specific certificate, the cert/key will be ''${keyStorePath}/''${device}/''${certificate}.{x509.pem,pk8}
              Otherwise, it will be ''${keyStorePath}/''${certificate}.{x509.pem,pk8}
              Finally, the special string "PRESIGNED" will just use the apk as-is.
            '';
          };

          snakeoilKeyPath = mkOption {
            type = types.path;
            internal = true;
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
            if config.certificate == "PRESIGNED" then config.apk else (pkgs.robotnix.signApk {
              inherit (config) apk;
              keyPath =
                if _config.signing.enable
                then _config.build.sandboxKeyPath config.certificate
                else "${config.snakeoilKeyPath}/${config.certificate}";
            }));

          fingerprint = let
              snakeoilFingerprint = pkgs.robotnix.certFingerprint "${config.snakeoilKeyPath}/${config.certificate}.x509.pem";
            in mkDefault (
            if config.certificate == "PRESIGNED"
              then pkgs.robotnix.apkFingerprint config.signedApk # TODO: IFD
              else if (!_config.signing.enable)
                then
                  builtins.trace ''
                    Used IFD to get fingerprint of reproducible app certificate.
                    Recommend setting:
                    apps.prebuilt.${config.name}.fingerprint = mkIf (!config.signing.enable) "${snakeoilFingerprint}"
                    ''
                    snakeoilFingerprint
                else _config.build.fingerprints config.certificate
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
    source.dirs = listToAttrs (map (prebuilt: {
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
        '' + optionalString ((prebuilt.certificate != "PRESIGNED") && !(builtins.elem prebuilt.certificate deviceCertificates)) ''
          cp ${prebuilt.snakeoilKeyPath}/${prebuilt.certificate}.{pk8,x509.pem} $out/
        '');
      };
    }) (attrValues cfg));

    # TODO: Make just a single file with each of these configuration types instead of one for each app?
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

    system.additionalProductPackages = map (p: "Robotnix${p.name}") (filter (p: p.partition == "system") (attrValues cfg));
    product.additionalProductPackages = map (p: "Robotnix${p.name}") (filter (p: p.partition == "product") (attrValues cfg));

    # Convenience derivation to get all prebuilt apks -- for use in custom fdroid repo?
    build.prebuiltApks = pkgs.linkFarm "${config.device}-prebuilt-apks"
      (map (p: { name="${p.name}.apk"; path=p.signedApk; })
      (filter (p: p.name != "CustomWebview") (attrValues cfg)));
  };
}
