<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# Building

## Build outputs

Robotnix provides a number of Nix outputs that can be built with a given configuration.
The specific output is selected using the `-A` option of `nix-build`.
For example, the following will build an `img` zip associated with the configuration in `config.nix`.
```shell
$ nix-build --arg configuration ./config.nix -A img
```

Some of the outputs provided by robotnix are the following:
- `img` - Image zip, which can be flashed to a device using `fastboot update`.
- `factoryImg` - Factory image, a zip which contains the contents of `img` as well as a radio / bootloader if available.
- `ota` - Over-the-air zip, which can be flashed to a device in recovery mode using `adb sideload`.
- `releaseScript` - Script which produces the `img`, `ota`, and `factoryImg` products outside of Nix.
- `generateKeysScript` - Script to generate required device / application keys for a given configuration.

## Building and Signing Releases
After creating a configuration file, you need to generate keys for your device (if you are using signed builds, with `signing.enable = true;`):
```console
$ nix-build --arg configuration ./crosshatch.nix -A generateKeysScript -o generate-keys
$ ./generate-keys ./keys
```
This will create a `keys` directory containing the app and device keys needed for the build.
The output of this script should be placed in the location specified by `signing.keyStorePath` in the robotnix configuration.
If you intend to build the `img`/`factoryImg`/`ota` Nix outputs instead of using the `releaseScript`, do not apply a passphrase to your keys here.
(You can still encrypt them at rest on your own through other means.)
This is because we cannot prompt you for your passphrase during the Nix build, but we can outside of Nix using `generateKeysScript`.

Sometimes changing your configuration will require that you generate additional new keys (e.g. for additional applications).
Rebuilding and rerunning the generate keys script will produce the new keys (without overwriting your existing keys).

Next, build and sign your release.
There are two ways to do this.
The first option is to build the final products entirely inside Nix.
```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A img --option extra-sandbox-paths /keys=$(pwd)/keys
```
This, however, will require a nix sandbox exception so the secret keys are available to the build scripts.
To use `extra-sandbox-paths`, the user must be a `trusted-user` in `nix.conf`.
Additionally, the nix builder will also need read access to these keys.
This can be set using `chgrp -R nixbld ./keys` and `chmod -R g+r ./keys`.

The second option involves creating a "release script" which does the final build steps of signing target files and creating `img`/`ota` files outside of Nix:
```console
$ nix-build --arg configuration ./crosshatch.nix -A releaseScript -o release
$ ./release ./keys
```
This has the additional benefit that the build can take place on a remote machine, and the `releaseScript` could be copied using `nix-copy-closure` to a local machine which containing the keys.
You might need to manually set certain required options like `signing.avb.fingerprint` or `apps.prebuilt.<name>.fingerprint` if you build on a remote machine that does not have access to the `signing.keyStorePath`.

## Binary Cache
Robotnix now has an optional binary cache provided by [Cachix](https://cachix.org/) on [robotnix.cachix.org](https://robotnix.cachix.org/).
Using the robotnix binary cache will allow the user to avoid building some parts that can be shared between users.
Currently, only the device kernels and browser builds are published through the binary cache.
This is because these derivation outputs are most likely to be shared between users, and those outputs also can take a very long time to build.
The build products previously discussed should be uploaded for at least every robotnix release tag.
To use, install `cachix`, run `cachix use robotnix`, and then build robotnix like normal.

## Flakes
If the robotnix configuration is specified in a flake, the robotnix outputs can be produced by running (for example):
```shell
$ nix build .#robotnixConfigurations.dailydriver.img
```
This is assuming the `flake.nix` is in the current directory, the desired configuration is named `dailydriver`, and will produce the `img` output.
Other robotnix outputs are available using a similar command.
