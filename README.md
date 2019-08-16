# NixDroid

This is a fork of the original NixDroid, focusing on recent customized vanilla-ish AOSP targeting Pixel devices.
This fork additionally uses a NixOS-style module system for configuring the build.
It also has partial support for building GrapheneOS, but currently doesn't build Vanadium (GrapheneOS's chromium fork).

To begin, create a configuration file, see `example.nix`, `marlin.nix`, and `crosshatch.nix` for inspiration.
This has only been tested on marlin (Pixel XL) and crosshatch (Pixel 3 XL), but should support all Pixel devices with (hopefully) minor changes.

#### Building the vanilla AOSP ROM:

Generate keys to sign your build:

```console
$ nix-build ./default.nix --arg configuration ./marlin.nix -A config.build.generateKeysScript -o generate-keys
$ mkdir keys/marlin
$ cd keys/marlin
$ ../generate-keys "/CN=NixDroidOS" # Use appropriate x509 cert fields
$ cd ../..
```

Build and sign your release:

```console
$ nix-build ./default.nix --arg configuration ./marlin.nix -A config.build.releaseScript -o release
$ ./release ./keys/marlin
```

An alternative to using the releaseScript above is to build the final products using nix with a sandbox exception for secret keys, so the build process can sign things itself.

```console
$ nix-build ./default.nix --arg configuration ./marlin.nix -A config.build.img --option extra-sandbox-paths /keys=$(pwd)/keys
```
To use `extra-sandbox-paths`, the user must be a `trusted-user` in `nix.conf`.
The root user is always trusted, however, running `sudo nix-build ...` would use root's git cache for `builtins.fetchgit`, which would effectively re-download the source again.

Other built targets include `config.build.ota`, and `config.build.otaDir`.
