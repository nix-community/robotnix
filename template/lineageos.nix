{
  config,
  lib,
  pkgs,
  ...
}:
{
  flavor = "lineageos";

  # device codename - FP4 for Fairphone 4 in this case.
  # Supported devices are listed under https://wiki.lineageos.org/devices/
  device = "FP4";

  # LineageOS branch.
  # You can check the supported branches for your device under
  # https://wiki.lineageos.org/devices/<device codename>
  # Leave out to choose the official default branch for the device.
  flavorVersion = "23.0";

  apps.fdroid.enable = true;
  microg.enable = true;

  # Enables ccache for the build process. Remember to add /var/cache/ccache as
  # an additional sandbox path to your Nix config.
  ccache.enable = true;
}
