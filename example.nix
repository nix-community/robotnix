{ config, pkgs, lib, ... }:

with pkgs;
with lib;
{
  flavor = "grapheneos"; # "vanilla" is another option

  # Don't forget to update these for each unique build
  buildNumber = "2019.09.12.2";
  buildDateTime = 1568321143;

  # A _string_ of the path for the key store.
  keyStorePath = "/var/secrets/android-keys";

  apps = {
    webview = {
      enable = true;
      description = "Bromite";
      packageName = "com.android.webview";
      apk = fetchurl {
        url = "https://github.com/bromite/bromite/releases/download/76.0.3809.129/arm64_SystemWebView.apk";
        sha256 = "0mdp2bmc0kvcnfd1yqiq9l18jg8a0vi9bbnfzllpvd5n5w42ir53";
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
  microg.enable = true;
  # Using cloud messaging, so enabling: https://source.android.com/devices/tech/power/platform_mgmt#integrate-doze
  resources."frameworks/base/core/res".config_enableAutoPowerModes = true;

  google.fi.enable = true;
}
