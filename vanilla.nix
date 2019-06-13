with (import <nixpkgs> {});
import ./default.nix rec {
  device = "marlin"; # Pixel XL
  rev = "android-9.0.0_r40";
  buildID = "PQ3A.190605.003.2";
  buildType = "user";
  manifest = "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
  sha256 = "0bmy1zm5mjwkly5jrcc0byr2mfm23z2akglz8q5pys0c5rnhyhzz";
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

  #enableWireguard = true; # My version doesn't use the roomservice stuff
  # The apk needs root to use the kernel features anyway...

  monochromeApk = fetchurl {
    url = "https://github.com/andi34/prebuilts_chromium/raw/master/MonochromePublic.apk";
    sha256 = "175cw8z06lx52204affpb4a9kmjrkqb0byhky817mb85cg1dh3dz";
  };
  releaseUrl = "https://daniel.fullmer.me/android/"; # Needs trailing slash
}
