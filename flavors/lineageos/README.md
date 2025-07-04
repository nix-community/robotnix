# LineageOS

Robotnix should support [all devices that are officially supported by LineageOS too](https://wiki.lineageos.org/devices/).

Example config:
```nix
{
    inputs.robotnix.url = "github:nix-community/robotnix";

    outputs = { self, robotnix }: {
        myLineageSystem = robotnix.lib.robotnixSystem (
        { config, lib, pkgs, ... }: {
            flavor = "lineageos";
            device = "FP4";

            # LineageOS branch.
            # You can check the supported branches for your device under
            # https://wiki.lineageos.org/devices/<device codename>
            flavorVersion = "22.2";

            apps.fdroid.enable = true;
            microg.enable = true;
        });
    };
}
```

To build the OTA zip file:
```console
$ nix build .#myLineageSystem.ota
```
