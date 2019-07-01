with (import <nixpkgs> {});
import ./default.nix rec {
  device = "marlin"; # Pixel XL
  rev = "16bjla28mkaiia9x6rb7gx5838n6i1vrm09m6blw9gh8nh28ki24";
  buildID = "2019.06.23.05"; # PQ3A.190605.003.2019.06.23.05
  buildType = "user";
  manifest = "https://github.com/GrapheneOS/platform_manifest.git";
  sha256 = "1r7xsb8prnxgi3lxqbxdim6y69rc94sd6lf0rgl21wdx8c8k90mg";
  localManifests = [
    ./roomservice/misc/fdroid.xml
    ./roomservice/misc/backup.xml
  ];
  additionalProductPackages = [ "F-DroidPrivilegedExtension" "Backup" ]; # Chromium and updater already included upstream

  additionalPatches = [
    ./patches/fdroid.patch
  ];

  vendorImg = fetchurl {
    url = "https://dl.google.com/dl/android/aosp/marlin-pq3a.190605.003-factory-14ebecf7.zip";
    sha256 = "1gyhkl79vs63dg42rkwy3ki3nr6d884ihw0lm3my5nyzkzvyrsql";
  };
  kernelSrc = builtins.fetchGit { # TODO: GrapheneOS platform_manifest already fetches this. Use that instead.
    url = "https://github.com/GrapheneOS/kernel_google_marlin";
    rev = "d1823557f8535fd0383571cc627f633310635128"; # Latest as of 2019-06-28
  };
  verityx509 = ./keys/verity.x509.pem; # Only needed for marlin/sailfish

  systemWebViewApk = fetchurl {
    url = "https://github.com/bromite/bromite/releases/download/75.0.3770.109/arm64_SystemWebView.apk";
    sha256 = "1jlhf3np7a9zy0gjsgkhykik4cfs5ldmhgb4cfqnpv4niyqa9xxx";
  };
  webViewName = "Bromite";

  releaseUrl = "https://daniel.fullmer.me/android/"; # Needs trailing slash
}
