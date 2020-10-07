{ config, pkgs, apks, lib, ... }:

with lib;
let
  # aapt2 from android build-tools doesn't work here:
  # error: failed to deserialize resources.pb: duplicate configuration in resource table.
  # The version from chromium works, however:  https://bugs.chromium.org/p/chromium/issues/detail?id=1106115
  #aapt2 = "${pkgs.androidPkgs.sdk (p: with p.stable; [ tools build-tools-30-0-1 ])}/share/android-sdk/build-tools/30.0.1/aapt2";
  aapt2 = pkgs.stdenv.mkDerivation { # TODO: Move this into the chromium derivation. Use their own aapt2/bundletool.
    name = "aapt2";
    src = pkgs.fetchcipd {
      package = "chromium/third_party/android_build_tools/aapt2";
      version = "R2k5wwOlIaS6sjv2TIyHotiPJod-6KqnZO8NH-KFK8sC";
      sha256 = "1kkq9wjwnagaaksnifcs3j4k739k39rv5klm4p99bf6vw6wh6jm0";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    installPhase = "mkdir -p $out/bin && cp aapt2 $out/bin/";
  } + "/bin/aapt2";

  # Create a universal apk from an "android app bundle"
  aab2apk = aab: pkgs.runCommand "aab-universal.apk" { nativeBuildInputs = with pkgs; [ bundletool unzip ]; } ''
    bundletool build-apks build-apks --bundle ${aab}  --output result.apks --mode universal --aapt2 ${aapt2}
    unzip result.apks universal.apk
    mv universal.apk $out
  '';
in
{
  options = {
    apps.chromium.enable = mkEnableOption "chromium browser";
    apps.bromite.enable = mkEnableOption "bromite browser";
    apps.vanadium.enable = mkEnableOption "vanadium browser";
  };

  config = (mkMerge (flatten (map
    ({name, displayName, chromeModernIsBundled ? false}: let
      # There is a lot of shared code between chrome app and chrome webview. So we
      # build them in a single derivation. This is not optimal if the user is
      # enabling/disabling the apps/webview independently, but the benefits
      # outweigh the costs.
      packageName = "org.robotnix.${name}"; # Override package names here so we don't have to worry about conflicts
      webviewPackageName = "org.robotnix.${name}.webview";

      #isTriChrome = (config.androidVersion >= 10) && config.apps.${name}.enable && config.webview.${name}.enable;
      isTriChrome = false; # FIXME: Disable trichrome for now since it depends on a certificate and breaks nix caching

      browser = apks.${name}.override ({ customGnFlags ? {}, ... }: {
        targetCPU = { arm64 = "arm64"; arm = "arm"; x86_64 = "x64"; x86 = "x86";}.${config.arch};
        buildTargets =
          if isTriChrome then [ "trichrome_webview_apk" "trichrome_chrome_bundle" "trichrome_library_apk" ]
          else
            (optional (config.apps.${name}.enable && chromeModernIsBundled) "chrome_modern_public_bundle") ++
            (optional (config.apps.${name}.enable  && !chromeModernIsBundled) "chrome_modern_public_apk") ++
            (optional config.webview.${name}.enable "system_webview_apk");
          inherit packageName webviewPackageName displayName;
          customGnFlags = customGnFlags // optionalAttrs isTriChrome {
            # Lots of indirection here. If not careful, it might cause infinite recursion.
            trichrome_certdigest = toLower config.apps.prebuilt."${name}TrichromeLibrary".fingerprint;
          };
      });
    in [
      (mkIf (config.apps.${name}.enable) {
        apps.prebuilt.${name}.apk =
          if isTriChrome then aab2apk "${browser}/TrichromeChrome.aab"
          else if chromeModernIsBundled then aab2apk "${browser}/ChromeModernPublic.aab"
          else "${browser}/ChromeModernPublic.apk";
      })

      { # Unconditionally fill out the apk/description here, but it will not be included unless webview.<name>.enable = true;
        webview.${name} = {
          packageName = webviewPackageName;
          description = "${displayName} WebView";
          apk =
            if isTriChrome
            then "${browser}/TrichromeWebView.apk"
            else "${browser}/SystemWebView.apk";
        };
      }

      (mkIf isTriChrome {
        apps.prebuilt."${name}TrichromeLibrary".apk = "${browser}/TrichromeLibrary.apk";
      })
    ])
    [ { name = "chromium"; displayName = "Chromium"; chromeModernIsBundled = true; }
      { name = "bromite"; displayName = "Bromite"; chromeModernIsBundled = true; }
      { name = "vanadium"; displayName = "Vanadium"; }
    ]
  )));
}

