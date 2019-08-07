# NixDroid

This is a fork focusing on recent vanilla AOSP.
It also has preliminary support for building GrapheneOS, but currently can't build their chromium fork.
This fork additionally uses a NixOS-style module system for configuring the build.

To begin, create a configuration file, see `example.nix`, `marlin.nix`, and `crosshatch.nix` for inspiration.
This has only been tested on marlin (Pixel XL), but should support all Pixel devices with minor changes.

#### Building the vanilla AOSP ROM:

Generate keys to sign your build:

```console
$ nix-build ./default.nix --arg configuration "import ./marlin.nix" -A config.build.generateKeysScript -o generate-keys
$ mkdir keys/marlin
$ cd keys/marlin
$ ../generate-keys "/CN=NixDroidOS" # Use appropriate x509 cert fields
$ cd ../..
```

Build and sign your release:

```console
$ nix-build ./default.nix --arg configuration "import ./marlin.nix" -A config.build.releaseScript -o release
$ ./release ./keys/marlin
```

### Building final products in nix with a sandbox exception for secret keys
```console
$ nix-build ./default.nix --arg configuration "import ./marlin.nix" -A config.build.img --option extra-sandbox-paths /keys=$(pwd)/keys
```
To use `extra-sandbox-paths`, the user must be a `trusted-user` in `nix.conf`.
The root user is always trusted, however, running `sudo nix-build ...` would use root's git cache for `builtins.fetchgit`, which would effectively re-download the source again.

Other options include `ota`, and `otaDir`.

chgrp nixbld is one option

Why do we pass the entire keys direcory in when we only need one specific device's keys?
building a linkFarm of otaDirs for multiple devices can still alll use the same /keys dir
