# LineageOS

Robotnix should support [all devices that are officially supported by LineageOS too](https://wiki.lineageos.org/devices/), although only `FP4` is tested right now.

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


## Internals

In addition to AOSP git-repo, LineageOS has its own even more questionable
device-specific dependency management system inherited from CyanogenMod.
Device-specific dependencies are specified via the `lineage.dependencies`
files, and handled in
[roomservice.py](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-22.2/build/tools/roomservice.py)
in the `android_vendor_lineage` repository.

The device-specific dependency management is invoked by running `breakfast
<device>` at build time. `roomservice.py` will then look up the [LineageOS
mirror
manifest](https://raw.githubusercontent.com/LineageOS/mirror/main/default.xml),
search for repos matching the regex `android_device_[^_]*_<device>`, clone that
repo, read its `lineage.dependencies` file, and recursively download the
required dependencies. The official default branches of the supported devices
are specified in [LineageOS/hudson](https://github.com/LineageOS/hudson).

The `repo-tool get-lineage-devices` command first looks up LineageOS/hudson to
get a list of all devices (and some additional metadata like the vendor names),
and then searches through the repo list from the LineageOS mirror manifest to
find the respective device tree repos. Then, it ls-remotes the device tree
repos to get a list of the LineageOS branches available for the device. It then
saves the acquired information in an output file (called `devices.json` here).

Then, `repo-tool fetch` can be invoked with the `-l/--lineage-device-file
devuces.json` argument. It will then recursively go through the
`lineage.dependencies` files of all device repos specified in `devices.json`
and fetch and lock the required repos. Device-specific repos will be marked via
their `category` field in the lockfile.

Frequently, for unofficial LOS branches, some device-specific dependencies will
be missing. `repo-tool` will exclude that device from the further fetching
process and write it to the file specified by the `-m/--missing-dep-devices`
argument.

### Proprietary vendor files

repo-tool supports fetching the proprietary vendor file repos from the GitHub
`TheMuppets` org. You can enable this with the `--muppets` flag. If any of the
vendor file repos of some device are missing for the specified branch,
repo-tool will write that device to the file specified by
`-m/--missing-dep-devices` too.

### Adding an unofficial device

If you want to build LineageOS for a device that's not officially supported,
you can create a second devices file (for instance `my_devices.json`), and
declare the device(s) you want to build for in the same format as in the
auto-generated `devices.json` file. Then, re-run `repo-tool fetch` with the
additional device metadata file, for instance:

```console
$ repo-tool fetch -r lineage-22.2 -l devices.json -l my_devices.json --muppets https://github.com/LineageOS/android lineage-22.2/repo.lock -m lineage-22.2/missing_dep_devices.json
```

However, in case you are using your own device-specific repos outside the LineageOS
GitHub org, you should consider manually adding them in with the `source.dirs`
module option and thus bypassing the robotnix implementation of the LOS
dependency management due to its messy logic for inferring Git remotes and
branches (see [roomservice.py](https://github.com/LineageOS/android_vendor_lineage/blob/cb1091b3f51d5476f49d6dae27458cced842e59c/build/tools/roomservice.py#L169)).
