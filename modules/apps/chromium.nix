{ config, pkgs, apks, lib, ... }:

with lib;
let
  # There is a lot of shared code between chrome app and chrome webview. SO we
  # build them in a single derivation. This is not optimal if the user is
  # enabling/disabling the apps/webview independently, but the benefits
  # outweigh the costs.
  mkBrowser = name: apks.${name}.override {
    targetCPU = { arm64 = "arm64"; arm = "arm"; x86_64 = "x64"; x86 = "x86";}.${config.arch};
    buildTargets =
      (optional config.apps.${name}.enable "chrome_modern_public_apk") ++
      (optional config.webview.${name}.enable "system_webview_apk");
    packageName = "org.nixdroid.${name}"; # Override package names here so we don't have to worry about conflicts
    webviewPackageName = "org.nixdroid.${name}.webview";
  };
  chromium = mkBrowser "chromium";
  bromite = mkBrowser "bromite";
  vanadium = mkBrowser "vanadium";
in
{
  options = {
    apps.chromium.enable = mkEnableOption "chromium browser";
    apps.bromite.enable = mkEnableOption "bromite browser";
    apps.vanadium.enable = mkEnableOption "vanadium browser";
  };

  config = let
    mkAppCfg = name: browser:
      (mkIf (config.apps.${name}.enable) {
        apps.prebuilt.${name}.apk = "${browser}/ChromeModernPublic.apk";
      });
    mkWebViewCfg = name: displayName: browser: {
      webview.${name} = {
        packageName = "org.nixdroid.${name}.webview";
        description = "${displayName} WebView";
        apk = "${browser}/SystemWebView.apk";
      };
    };
  in (mkMerge [
    (mkAppCfg "chromium" chromium)
    (mkAppCfg "bromite" bromite)
    (mkAppCfg "vanadium" vanadium)

    # Fill out the apk/description here, but they will not be included unless webview.<name>.enable = true;
    (mkWebViewCfg "chromium" "Chromium" chromium)
    (mkWebViewCfg "bromite" "Bromite" bromite)
    (mkWebViewCfg "vanadium" "Vanadium" vanadium)
  ]);
}

