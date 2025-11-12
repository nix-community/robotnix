{ config, ... }: {
  flavor = "grapheneos";
  device = "tegu";

  grapheneos = {
    # This setting determines which GrapheneOS release tag will be built -
    # every channel assigns a "current release" tag to each device.
    channel = "stable";
  };

  apps.fdroid.enable = true;

  # Enables ccache for the build process. Remember to add /var/cache/ccache as
  # an additional sandbox path to your Nix config.
  ccache.enable = true;
}
