with (import <nixpkgs> {});
import ./default.nix rec {
  device = "marlin"; # Pixel XL
  rev = "android-9.0.0_r35";
  buildID = "PQ2A.190405.003";
  buildType = "userdebug";
  manifest = "https://android.googlesource.com/platform/manifest"; # I get 100% cpu usage and no progress with this URL. Needs older curl version
  sha256 = "0y7jn3bf58n8wlyd21kd9wn8ljwj4hqb9srfln4q5xn6r68n2czp";
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
  vendorImg = fetchurl {
    url = https://dl.google.com/dl/android/aosp/marlin-pq2a.190405.003-factory-d30b60f0.zip;
    sha256 = "01mic9phhsi0x7kv8l1jc01caqbxj65r4nshml6l6l38f7q602yk";
  };
}
