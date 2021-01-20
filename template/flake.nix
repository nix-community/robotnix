{
  description = "A basic example robotnix configuration";

  inputs = {
    robotnix.url = "github:danielfullmer/robotnix/flake"; # Currently only the flake branch has a flake.nix file
  };

  outputs = { self, robotnix }: {
    defaultPackage.x86_64-linux = self.robotnixConfigurations."dailydriver".img;

    robotnixConfigurations."dailydriver" = robotnix.robotnixSystem ({ config, pkgs, ... }: {
      # These two are required options
      device = "crosshatch";
      flavor = "vanilla"; # "grapheneos" is another option

      # buildDateTime is set by default by the flavor, and is updated when those flavors have new releases.
      # If you make new changes to your build that you want to be pushed by the OTA updater, you should set this yourself.
      # buildDateTime = 1584398664; # Use `date "+%s"` to get the current time

      # A _string_ of the path for the key store.
      # keyStorePath = "/var/secrets/android-keys";
      # signing.enable = true;

      # Build with ccache
      # ccache.enable = true;
    });
  };
}
