<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# Configuration

Similarly to [NixOS](https://nixos.org/), robotnix configurations are "Nix expressions" specified using the "[Nix language](https://nixos.org/manual/nix/stable/#ch-expression-language)."
Most end-user uses of robotnix should not require learning the Nix language, besides the very basics of syntax.

## Inline Configuration
Robotnix can be built using configuration specified on the command line using `--arg configuration ...` as an argument to `nix-build`.
For example, if the current directory contains a checked out copy of robotnix, the following will produce a vanilla image for the crosshatch device (Pixel 3 XL):
```shell
$ nix-build --arg configuration '{ device="crosshatch"; flavor="vanilla"; }' -A img
```
By default, `nix-build` uses the `default.nix` in the current directory as the Nix entry point.
If robotnix is checked out in another directory, such as `$HOME/src/robotnix`, the above command could instead be
```shell
$ nix-build $HOME/src/robotnix --arg configuration '{ device="crosshatch"; flavor="vanilla"; }' -A img
```

## Configuration Files
A configuration file should be created for anything more complicated than the very simple configurations that could be conveniently specified on the command line.
The following is an example robotnix configuration that could be saved to (for example) `crosshatch.nix`.
```nix
{
  # Most uses of robotnix should at least set the device and flavor options.
  device = "crosshatch";
  flavor = "vanilla";

  # variant = "user"; # Other options are userdebug, or eng. Builds used in production should use "user"

  # Signing should be enabled for builds used in production.
  signing.enable = true;
  # When signing is enabled, keyStorePath should refer to a path containing keys created by `genereteKeysScript`
  # This is used to automatically obtain key fingerprints / metadata from the generated public keys.
  # Alternatively, it may be possible to manually set the required options like `signing.avb.fingerprint` or `apps.prebuilt.<name>.fingerprint` to avoid including this path.
  signing.keyStorePath = "/var/secrets/android-keys";

  # Additional modules can be enabled and included in the build. See individual module documentation
  apps.fdroid.enable = true;
  microg.enable = true;
}
```

The `--arg configuration ...` option for `nix-build` can also refer to a `.nix` file containing the robotnix configuration.
If the above configuration was saved to `crosshatch.nix` in the local directory, an image could be built using the following command:
```shell
$ nix-build --arg configuration ./crosshatch.nix -A img
```

See my own configuration under `example.nix` for inspiration.
Reference documentation of the available options is [here](options.md).

## Flakes (experimental)
Nix flakes are an upcoming feature of Nix that provides an alternative configuration structure for use with the new `nix` command.
It can provide the benefit of explicitly pinning your robotnix configuration against a particular revision of the robotnix repository.
The feature remains experimental for the time-being, and is not currently the recommended way to use robotnix for new users.

Robotnix provides an example nix flake template, which can be used to prepopulate the current directory with the command `nix flake init -t github:danielfullmer/robotnix`.

Example usage:
```shell
$ mkdir flake-test
$ cd flake-test
$ nix flake init -t github:danielfullmer/robotnix
$ # Edit flake.nix in current directory
$ nix build .#robotnixConfigurations.dailydriver.img
```
