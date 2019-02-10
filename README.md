# NixDroid

You know how people build their Android ROMs with Jenkins and stuff?

Well, at some point I set up a Hydra for all my NixOS systems, which got me thinking: couldn't I be using this to build an Android ROM for my phone?

So I went ahead and did just that.

This has only been tested for LineageOS 15.1 and 16.0 for Moto X4 (payton) and OnePlus 3, but it should work for other roms and devices as well.

As the Wireguard tries to fetch the latest version during the build and internet access is not possible during a Nix build, the version number is hard coded in `wireguard.xml`.
You are free to use the `update-wireguard` script (on your regular system), which fetches the latest Wireguard version and writes it into the manifest.

#### TODO:

* Fix sha256 hash. We reference a repo "branch", so the hash is constantly changing. Not sure what the best approach would be.

* With the hash thing fixed: Actually put it in our Hydra.

* Sign builds. Right now, they are all signed with test-keys.
