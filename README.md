# NixDroid

You know how people build their Android ROMs with Jenkins and stuff?

Well, at some point I set up a Hydra for all my NixOS systems, which got me thinking: couldn't I be using this to build an Android ROM for my phone?

So I went ahead and did just that.

This has only been tested for LineageOS 15.1 and 16.0 for Moto X4 (payton), OnePlus 3 and Nexus 5, but it should work for other roms and devices as well.

As the Wireguard tries to fetch the latest version during the build and internet access is not possible during a Nix build, the version number is hard coded in `wireguard.xml`.
You are free to use the `update-wireguard` script (on your regular system), which fetches the latest Wireguard version and writes it into the manifest.

#### TODO:

* Document (e.g. which patches to nix are needed why)

* While the hash thing is kind of fixed, there is definitely room for improvement.
