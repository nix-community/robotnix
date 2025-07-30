{ config, lib, pkgs, ... }: {
  flavor = "lineageos";

  # device codename - FP4 for Fairphone 4 in this case.
  # Supported devices are listed under https://wiki.lineageos.org/devices/
  device = "FP4";

  # LineageOS branch.
  # You can check the supported branches for your device under
  # https://wiki.lineageos.org/devices/<device codename>
  flavorVersion = "22.2";

  apps.fdroid.enable = true;
  microg.enable = true;

  ccache.enable = true;
}
