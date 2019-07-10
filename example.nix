with (import <nixpkgs> {});
{
  imports = [ ./modules/profiles/grapheneos.nix ];
  device = "marlin";
  buildID = "2019.07.04.1";
  certs = {
    verity = ./keys/verity.x509.pem;  # Only necessary for marlin (Pixel XL) since the kernel build needs to include this cert
    platform = ./keys/platform.x509.pem;  # Used by fdroid privileged extension to whitelist org.fdroid.fdroid
  };
  apps = {
    webview = {
      enable = true;
      description = "Bromite";
      packageName = "com.android.webview";
      apk = fetchurl {
        url = "https://github.com/bromite/bromite/releases/download/75.0.3770.109/arm64_SystemWebView.apk";
        sha256 = "1jlhf3np7a9zy0gjsgkhykik4cfs5ldmhgb4cfqnpv4niyqa9xxx";
      };
    };

    updater.enable = true;
    updater.url = "https://daniel.fullmer.me/android/";

    backup.enable = true;
    fdroid.enable = true;
  };
  vendor.full = true; # Needed for Google Fi
}
