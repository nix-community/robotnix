with (import ./pkgs.nix);
{
  imports = [ ./modules/profiles/grapheneos.nix ];

  # Don't forget to update these for each unique build
  buildNumber = "2019.07.31.1";
  buildDateTime = 1564601006;


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
        url = "https://github.com/bromite/bromite/releases/download/76.0.3809.91/arm64_SystemWebView.apk";
        sha256 = "1il2qv8aknpll9g1an28qzk08iqfhmjypaypm422c2d592p9h482";
      };
    };

    updater.enable = true;
    updater.url = "https://daniel.fullmer.me/android/";

    backup.enable = true; # Set to default using: adb shell bmgr transport com.stevesoltys.backup.transport.ConfigurableBackupTransport
    fdroid.enable = true;

    # See the NixOS module in https://github.com/danielfullmer/nixos-config/modules/attestation-server.nix
    auditor.enable = true;
    auditor.domain = "attestation.daniel.fullmer.me";
  };

  microg.enable = true;
  # Using cloud messaging, so enabling: https://source.android.com/devices/tech/power/platform_mgmt#integrate-doze
  resources."frameworks/base/core/res".config_enableAutoPowerModes = true;
}
