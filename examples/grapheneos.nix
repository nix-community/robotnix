{ config, ... }: {
  flavor = "grapheneos";
  device = "tegu";

  grapheneos = {
    # This setting determines which GrapheneOS release tag will be built -
    # every channel assigns a "current release" tag to each device.
    channel = "stable";
  };

  apps.fdroid.enable = true;

  ccache.enable = true;

  # Not tested yet.
  signing.enable = false;
}
