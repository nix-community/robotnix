# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  apks,
  lib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkMerge
    mkEnableOption
    mkOverride
    ;

  mkWeakDefault = mkOverride 1200; # Priority betrween mkDefault and mkOptionDefault

  # aapt2 from android build-tools doesn't work here:
  # error: failed to deserialize resources.pb: duplicate configuration in resource table.
  # The version from chromium works, however:  https://bugs.chromium.org/p/chromium/issues/detail?id=1106115
  #aapt2 = "${pkgs.androidPkgs.sdk (p: with p; [ cmdline-tools-latest build-tools-30-0-1 ])}/share/android-sdk/build-tools/30.0.1/aapt2";
  aapt2 =
    pkgs.stdenv.mkDerivation {
      # TODO: Move this into the chromium derivation. Use their own aapt2/bundletool.
      name = "aapt2";
      src = pkgs.fetchcipd {
        package = "chromium/third_party/android_build_tools/aapt2";
        version = "O9eXFyC5ZkcYvDfHRLKPO1g1Xwf7M33wT3cuJtyfc0sC";
        sha256 = "0bv8qx7snyyndk5879xjbj3ncsb5yxcgp8w0wwfrif3m22d1fn84";
      };
      nativeBuildInputs = [ pkgs.autoPatchelfHook ];
      installPhase = "mkdir -p $out/bin && cp aapt2 $out/bin/";
    }
    + "/bin/aapt2";

  # Create a universal apk from an "android app bundle"
  aab2apk =
    aab:
    pkgs.runCommand "aab-universal.apk"
      {
        nativeBuildInputs = with pkgs; [
          bundletool
          unzip
        ];
      }
      ''
        bundletool build-apks build-apks --bundle ${aab}  --output result.apks --mode universal --aapt2 ${aapt2}
        unzip result.apks universal.apk
        mv universal.apk $out
      '';

  # This is the default cert used in chrome/android/trichrome.gni of chromium source
  defaultTrichromeCertDigest = "32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0";

  # Override the trichrome_certdigest in an already-built apk
  patchTrichromeApk =
    name: src: newCertDigest:
    pkgs.runCommand "${name}-trichrome-patched.apk"
      {
        nativeBuildInputs = with pkgs; [ python3 ];
      }
      ''
        python3 ${./chromium-trichrome-patcher.py} ${src} patched.apk ${lib.toLower defaultTrichromeCertDigest} ${lib.toLower newCertDigest}
        ${pkgs.robotnix.build-tools}/zipalign -p -f 4 patched.apk $out
      '';
in
{
  options = {
    apps.chromium.enable = mkEnableOption "chromium browser";
    apps.bromite.enable = mkEnableOption "bromite browser";
    apps.vanadium.enable = mkEnableOption "vanadium browser";
  };

  config = mkMerge (
    (lib.flatten (
      map
        (
          {
            name,
            displayName,
            buildSeparately ? false,
            chromeModernIsBundled ? true,
            isTriChrome ? (config.androidVersion >= 10),
          }:
          let
            # There is a lot of shared code between chrome app and chrome webview. So we
            # default to building them in a single derivation. This is not optimal if
            # the user is enabling/disabling the apps/webview independently, but the
            # benefits outweigh the costs.
            packageName = "org.robotnix.${name}"; # Override package names here so we don't have to worry about conflicts
            webviewPackageName = "org.robotnix.${name}.webview";
            trichromeLibraryPackageName = "org.robotnix.${name}.trichromelibrary";

            patchedTrichromeApk =
              componentName: apk:
              apk; #patchTrichromeApk "${name}-${componentName}" apk config.apps.prebuilt.${name}.fingerprint;

            _browser =
              buildTargets:
              apks.${name}.override (
                {
                  customGnFlags ? { },
                  ...
                }:
                {
                  inherit
                    packageName
                    webviewPackageName
                    trichromeLibraryPackageName
                    displayName
                    buildTargets
                    ;
                  targetCPU =
                    {
                      arm64 = "arm64";
                      arm = "arm";
                      x86_64 = "x64";
                      x86 = "x86";
                    }
                    .${config.arch};
                }
              );
            chromiumTargets =
              if isTriChrome then
                [
                  "trichrome_chrome_bundle"
                  "trichrome_library_apk"
                ]
              else if chromeModernIsBundled then
                [ "chrome_modern_public_bundle" ]
              else
                [ "chrome_modern_public_apk" ];
            webviewTargets =
              if isTriChrome then
                [
                  "trichrome_webview_apk"
                  "trichrome_library_apk"
                ]
              else
                [ "system_webview_apk" ];

            browser =
              if buildSeparately then
                pkgs.symlinkJoin {
                  inherit name;
                  paths =
                    lib.optional config.apps.${name}.enable (_browser chromiumTargets)
                    ++ lib.optional config.webview.${name}.enable (_browser webviewTargets);
                }
              else
                _browser (
                  lib.unique (
                    lib.optionals config.apps.${name}.enable chromiumTargets
                    ++ lib.optionals config.webview.${name}.enable webviewTargets
                  )
                );

          in
          [
            {
              apps.prebuilt.${name} = {
                apk =
                  if isTriChrome then
                    patchedTrichromeApk "browser" (aab2apk "${browser}/TrichromeChrome.aab")
                  else if chromeModernIsBundled then
                    aab2apk "${browser}/ChromeModernPublic.aab"
                  else
                    "${browser}/ChromeModernPublic.apk";
                enable = mkWeakDefault config.apps.${name}.enable;
              };

              # Unconditionally fill out the apk/description here, but it will not be included unless webview.<name>.enable = true;
              webview.${name} = {
                packageName = webviewPackageName;
                description = "${displayName} WebView";
                apk =
                  if isTriChrome then
                    patchedTrichromeApk "webview" "${browser}/TrichromeWebView.apk"
                  else
                    "${browser}/SystemWebView.apk";
              };

              build.${name} = browser; # Put here for convenience

              apps.prebuilt."${name}TrichromeLibrary" = {
                apk = "${browser}/TrichromeLibrary.apk";
                enable = mkWeakDefault (
                  isTriChrome && (config.apps.${name}.enable || config.webview.${name}.enable)
                );
                certificate = config.apps.prebuilt.${name}.certificate; # Share certificate with application
              };
            }
          ]
        )
        [
          {
            name = "chromium";
            displayName = "Chromium";
          }
          # For an unknown reason, Bromite fails to build chrome_modern_public_bundle
          # simultaneously with system_webview_apk as of 2020-12-22
          {
            name = "bromite";
            displayName = "Bromite";
            buildSeparately = true;
            isTriChrome = false;
          }
          {
            name = "vanadium";
            displayName = "Vanadium";
          }
        ]
    ))
  );
}
