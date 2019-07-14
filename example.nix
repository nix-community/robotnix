with (import <nixpkgs> {});
{
  imports = [ ./modules/profiles/grapheneos.nix ];
  device = "marlin";
  buildID = "2019.07.13.1"; # Don't forget to update for each unique build

  certs.verity.x509 = ./keys/verity.x509.pem;  # Only necessary for marlin (Pixel XL) since the kernel build needs to include this cert
  certs.platform.x509 = ./keys/platform.x509.pem;  # Used by fdroid privileged extension to whitelist org.fdroid.fdroid
  avb.pkmd = ./keys/avb_pkmd.bin; # Only needed for Pixel 2/3 (XL)

  apps = {
    webview = {
      enable = true;
      description = "Bromite";
      packageName = "com.android.webview";
      apk = fetchurl {
        url = "https://github.com/bromite/bromite/releases/download/75.0.3770.139/arm64_SystemWebView.apk";
        sha256 = "0kxlvc3asvi4dhqkps0nhmfljk5mq5lc6vihj2acc3z7r7gy9yx4";
      };
    };

    updater.enable = true;
    updater.url = "https://daniel.fullmer.me/android/";

    backup.enable = true;
    fdroid.enable = true;
  };
  vendor.full = true; # Needed for Google Fi
}
