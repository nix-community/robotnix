with (import ./pkgs.nix);
{
  imports = [ ./modules/profiles/grapheneos.nix ];

  # Don't forget to update these for each unique build
  buildNumber = "2019.08.22.1";
  buildDateTime = 1566529623;

  apps = {
    webview = {
      enable = true;
      description = "Bromite";
      packageName = "com.android.webview";
      apk = fetchurl {
        url = "https://github.com/bromite/bromite/releases/download/76.0.3809.115/arm64_SystemWebView.apk";
        sha256 = "1s01zw1ch0b2pmbw3s26pv1xqb9d2fkz6b2r9k0yqgysd5i2vjbj";
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

  # Custom hosts file
  hosts = fetchurl { # 2019-08-14
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/449a0d7f613e6518ede4f3333e94f8071d3f1cd3/hosts";
    sha256 = "1mcn77l2m45qms7ynww2hzx0d6mja03bzj4di0s9j7spycp4540i";
  };
  vendor.full = true; # Needed for Google Fi


  microg.enable = true;
  # Using cloud messaging, so enabling: https://source.android.com/devices/tech/power/platform_mgmt#integrate-doze
  resources."frameworks/base/core/res".config_enableAutoPowerModes = true;
}
