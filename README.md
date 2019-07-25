# NixDroid

This is a fork focusing on recent vanilla AOSP.
It also has preliminary support for building GrapheneOS, but currently can't build their chromium fork.
This fork additionally uses a NixOS-style module system for configuring the build.

To begin, create a configuration file, see `example.nix` for inspiration.
This has only been tested on  marlin (Pixel XL), but should support all Pixel devices with minor changes.

#### Building the vanilla AOSP ROM:

Generate keys to sign your build:

```console
$ nix-build ./default.nix --arg configuration "import ./example.nix" -A generateKeysScript -o generate-keys
$ mkdir keys/marlin
$ cd keys/marlin
$ ../generate-keys "/CN=NixDroidOS" # Use appropriate x509 cert fields
$ cd ../..
```

Build and sign your release:

```console
$ nix-build ./default.nix --arg configuration "import ./example.nix" -A releaseScript -o release
$ ./release ./keys/marlin
```
