{ config, pkgs, lib, ... }:

with lib;
let
  boolToString = b: if b then "true" else "false";
  config_webview_packages = pkgs.writeText "config_webview_packages.xml" (''
    <?xml version="1.0" encoding="utf-8"?>
    <webviewproviders>
  '' +
  (lib.concatMapStringsSep "\n"
    (m: lib.optionalString m.enable
      "<webviewprovider description=\"${m.description}\" packageName=\"${m.packageName}\" availableByDefault=\"${boolToString m.availableByDefault}\" isFallback=\"${boolToString m.isFallback}\"></webviewprovider>")
    (attrValues config.webview)
  ) +
  ''

    </webviewproviders>
  '');
in
{
  options = {
    webview = mkOption {
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

          availableByDefault = mkOption { # TODO: Ensure only one of these is set
            type = types.bool;
            default = false;
            description = ''
              If true, this provider can be automatically
              selected by the framework, if it's the first valid choice. If
              false, this provider will only be used if the user selects it
              themselves from the developer settings menu.
            '';
          };

          isFallback = mkOption { # TODO: Ensure only one of these is set
            type = types.bool;
            default = false;
            description = ''
              If true, this provider will be automatically
              disabled by the framework, preventing it from being used or updated
              by app stores, unless there is no other valid provider available.
              Only one provider can be a fallback.
            '';
          };

          apk = mkOption {
            type = types.path;
          };
        };
      }));
    };
  };

  config = {
    apps.prebuilt = lib.mapAttrs' (name: m: nameValuePair "Webview${name}" {
      inherit (m) apk;

      # Extra stuff from the Android.mk from the example webview module in AOSP. Unsure if these are needed.
      extraConfig = ''
        LOCAL_MULTILIB := both
        LOCAL_REQUIRED_MODULES := \
          libwebviewchromium_loader \
          libwebviewchromium_plat_support
        LOCAL_MODULE_TARGET_ARCH := arm64
      '';
    }) (filterAttrs (name: m: m.enable) config.webview);

    # TODO: Replace this with something in the overlay
    source.dirs."frameworks/base".postPatch = ''
      cp --no-preserve=all -v ${config_webview_packages} core/res/res/xml/config_webview_packages.xml
    '';
  };
}
