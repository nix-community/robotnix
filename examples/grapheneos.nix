{ config, ... }: {
  flavor = "grapheneos";
  device = "tokay";

  androidVersion = 16;
  grapheneos = {
    # This setting determines which GrapheneOS release tag will be built -
    # every channel assigns a "current release" tag to each device.
    channel = "stable";
  };

  apps.fdroid.enable = true;
  microg.enable = true;

  ccache.enable = true;
}
