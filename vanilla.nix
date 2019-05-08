with (import <nixpkgs> {});
import ./default.nix rec {
  device = "marlin"; # Pixel XL
  rev = "android-9.0.0_r36";
  buildID = "PQ3A.190505.001";
  buildType = "user";
  manifest = "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
  sha256 = "1fskk125zh0dy4f45z2fblik4sqjgc0w8amclw6a281kpyhji4zp";
  localManifests = [
    (writeTextFile {
      name = "fdroid.xml";
      text = (import ./roomservice/misc/fdroid.xml.nix {
        fdroidClientVersion = "1.5.1"; # FDROID_CLIENT_VERSION
        fdroidPrivExtVersion = "0.2.9"; # FDROID_PRIV_EXT_VERISON
      });
    })
    (writeTextFile {
      name = "rattlesnakeos.xml";
      text = (import ./roomservice/rattlesnakeos.xml.nix {
        androidVersion = "9.0"; # ANDROID_VERSION
      });
    })
  ];
  additionalProductPackages = [ "Updater" "F-DroidPrivilegedExtension" ];
  removedProductPackages = [ "webview" "Browser2" "Calendar2" "QuickSearchBox" ];
  vendorImg = fetchurl {
    url = "https://dl.google.com/dl/android/aosp/marlin-pq3a.190505.001-factory-5dac573c.zip";
    sha256 = "0cd3zhvw9z8jjhrx43i9lhr0v7qff63vzw4wis5ir2mrxly5gb2x";
  };
}
