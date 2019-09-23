{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.webview;
  config_webview_packages = pkgs.writeText "config_webview_packages.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <webviewproviders>
      <webviewprovider description="${cfg.description}" packageName="${cfg.packageName}" availableByDefault="true">
      </webviewprovider>
    </webviewproviders>
  '';
in
{
  options = {
    apps.webview = { # TODO: multiple webviews?
      enable = mkEnableOption "custom webview";

      packageName = mkOption {
        type = types.str;
        default = "com.android.webview";
      };

      description = mkOption {
        type = types.str;
        default = "Chromium";
      };

      apk = mkOption {
        type = types.path;
      };
    };
  };

  config = mkIf cfg.enable {
    apps.prebuilt.CustomWebview = {
      inherit (cfg) apk;

      # Extra stuff from the Android.mk from the example webview module in AOSP. Unsure if these are needed.
      extraConfig = ''
        LOCAL_MULTILIB := both
        LOCAL_REQUIRED_MODULES := \
          libwebviewchromium_loader \
          libwebviewchromium_plat_support
        LOCAL_MODULE_TARGET_ARCH := arm64
      '';
    };

    # TODO: Replace this with something in the overlay
    source.dirs."frameworks/base".postPatch = ''
      cp --no-preserve=all -v ${config_webview_packages} core/res/res/xml/config_webview_packages.xml
    '';
  };
}
