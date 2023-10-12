# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkOption mkEnableOption types;
in
{
  options = {
    webview = mkOption {
      description = "Webview providers to include in Android build. Pre-specified options are `chromium`, `bromite`, and `vanadium`.";
      example = lib.literalExample "{ bromite.enable = true; }";

      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          enable = mkEnableOption "${name} webview";

          packageName = mkOption {
            type = types.str;
            default = "com.android.webview";
            description = "The Android package name of the APK.";
          };

          description = mkOption {
            type = types.str;
            default = "Android System WebView";
            description = "The name shown to the user in the developer settings menu.";
          };

          availableByDefault = mkOption {
            type = types.bool;
            default = false;
            description = ''
              If `true`, this provider can be automatically selected by the
              framework, if it's the first valid choice. If `false`, this
              provider will only be used if the user selects it themselves from
              the developer settings menu.
            '';
          };

          isFallback = mkOption {
            type = types.bool;
            default = false;
            description = ''
              If `true`, this provider will be automatically disabled by the
              framework, preventing it from being used or updated by app
              stores, unless there is no other valid provider available.  Only
              one provider can be a fallback.
            '';
          };

          apk = mkOption {
            type = types.path;
            description = "APK file containing webview package.";
          };

          extraConfig = mkOption {
            type = types.lines;
            description = "extra module configuration to include with the apk";
            default = "";
          };

          usesLibraries = mkOption {
            type = types.listOf types.str;
            default = [];
          };
        };
      }));
    };
  };

  config = mkIf (lib.any (m: m.enable) (lib.attrValues config.webview)) {
    assertions = [
      { assertion = lib.any (m: m.enable && m.availableByDefault) (lib.attrValues config.webview);
        message = "Webview module is enabled, but no webview has availableByDefault = true";
      }
      { assertion = lib.length (lib.filter (m: m.enable && m.isFallback) (lib.attrValues config.webview)) <= 1;
        message = "Multiple webview modules have isFallback = true";
      }
    ];

    apps.prebuilt = lib.mapAttrs' (name: m: lib.nameValuePair "${name}webview" {
      inherit (m) apk extraConfig;

      # Don't generate a cert if it's the prebuilt version from upstream
      certificate = if (name != "prebuilt") then "${name}webview" else "PRESIGNED";
    }) (lib.filterAttrs (name: m: m.enable) config.webview);

    product.extraConfig = "PRODUCT_PACKAGE_OVERLAYS += robotnix/webview-overlay";

    source.dirs."robotnix/webview-overlay".src = pkgs.writeTextFile {
      name = "config_webview_packages.xml";
      text =  ''
        <?xml version="1.0" encoding="utf-8"?>
        <webviewproviders>
      '' +
      (lib.concatMapStringsSep "\n"
        (m: lib.optionalString m.enable
          "<webviewprovider description=\"${m.description}\" packageName=\"${m.packageName}\" availableByDefault=\"${lib.boolToString m.availableByDefault}\" isFallback=\"${lib.boolToString m.isFallback}\"></webviewprovider>")
        (lib.attrValues config.webview)
      ) +
      ''
        </webviewproviders>
      '';
      destination = "/frameworks/base/core/res/res/xml/config_webview_packages.xml";
    };
  };
}
