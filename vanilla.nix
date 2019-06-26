with (import <nixpkgs> {});
import ./default.nix rec {
  device = "marlin"; # Pixel XL
  rev = "android-9.0.0_r40";
  buildID = "2019.06.26"; # A preferably unique string representing this build.
  buildType = "user";
  manifest = "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
  sha256 = "1p4d20yh44dkryimkkl8y76yr3wswq7rf343294z472l7zgl6yiz";
  localManifests = [
    ./roomservice/grapheneos.xml # Updater and external chromium
    ./roomservice/misc/fdroid.xml
    ./roomservice/misc/backup.xml
  ];
  additionalProductPackages = [ "Updater" "F-DroidPrivilegedExtension" "Chromium" "Backup" ];
  removedProductPackages = [ "webview" "Browser2" "Calendar2" "QuickSearchBox" ];
  vendorImg = fetchurl {
    url = "https://dl.google.com/dl/android/aosp/marlin-pq3a.190605.003-factory-14ebecf7.zip";
    sha256 = "1gyhkl79vs63dg42rkwy3ki3nr6d884ihw0lm3my5nyzkzvyrsql";
  };
  msmKernelRev = "521aab6c130d4ed21c67437cea44af4653583760";
  verityx509 = ./keys/verity.x509.pem; # Only needed for marlin/sailfish

  # The apk needs root to use the kernel features anyway...
  #enableWireguard = true;

  #monochromeApk = ./MonochromePublic.apk;
  systemWebViewApk = fetchurl {
    url = "https://github.com/bromite/bromite/releases/download/75.0.3770.109/arm64_SystemWebView.apk";
    sha256 = "1jlhf3np7a9zy0gjsgkhykik4cfs5ldmhgb4cfqnpv4niyqa9xxx";
  };
  webViewName = "Bromite";

  releaseUrl = "https://daniel.fullmer.me/android/"; # Needs trailing slash
}
