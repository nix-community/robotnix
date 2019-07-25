with (import <nixpkgs> {});
{
  imports = [ ./modules/profiles/grapheneos.nix ];
  device = "marlin";
  buildID = "2019.07.18.1"; # Don't forget to update for each unique build

  certs.verity.x509 = ./keys/marlin/verity.x509.pem;  # Only necessary for marlin (Pixel XL) since the kernel build needs to include this cert
  certs.platform.x509 = ./keys/marlin/platform.x509.pem;  # Used by fdroid privileged extension to whitelist org.fdroid.fdroid

  # Custom hosts file
  hosts = fetchurl { # 2019-07-17
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/e54e1d624ce335ba9611d7de5f108dd1f87b308d/hosts";
    sha256 = "0jkc376y938f3b7s1dmfbg1cf087rdmkv5f0469h60dbmryvxm10";
  };
  vendor.full = true; # Needed for Google Fi

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

    # See the NixOS module in https://github.com/danielfullmer/nixos-config/modules/attestation-server.nix
    auditor.enable = true;
    auditor.domain = "attestation.daniel.fullmer.me";
  };
}
