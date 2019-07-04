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
  chromiumAndroidmk = pkgs.writeText "Android.mk" ''
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := Chromium
LOCAL_MODULE_CLASS := APPS
LOCAL_MULTILIB := both
LOCAL_CERTIFICATE := $(DEFAULT_SYSTEM_DEV_CERTIFICATE)
LOCAL_REQUIRED_MODULES := \
    libwebviewchromium_loader \
    libwebviewchromium_plat_support

LOCAL_MODULE_TARGET_ARCH := arm64
LOCAL_SRC_FILES := prebuilt/arm64/SystemWebView.apk

include $(BUILD_PREBUILT)
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
    additionalProductPackages = [ "Chromium" ];

    postPatch = ''
      cp --no-preserve=all -v ${config_webview_packages} frameworks/base/core/res/res/xml/config_webview_packages.xml
      mkdir -p external/chromium/prebuilt/arm64
      cp --no-preserve=all -v ${chromiumAndroidmk} external/chromium/Android.mk
      cp --no-preserve=all -v ${cfg.apk} external/chromium/prebuilt/arm64/SystemWebView.apk
    '';
  };
}
