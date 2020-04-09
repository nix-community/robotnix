# robotnix - Building Android (AOSP) with Nix

This project enables using [Nix](https://nixos.org/nix/) to build (optionally customized) Android targeting Pixel devices.
Some features include:
 - A NixOS-style module system for customizing various aspects of the build
 - Signed builds for verified boot (dm-verity/AVB) and re-locking the bootloader
 - Android 10 support
 - [GrapheneOS](https://grapheneos.org/) support
 
Some optional nixos-style modules include:
 - Apps: [F-Droid](https://f-droid.org/) (including the privileged extention for automatic installation/updating), [Auditor](https://attestation.app/about), [Backup](https://github.com/stevesoltys/backup)
 - Browser / Webview: [Chromium](https://www.chromium.org/Home), [Bromite](https://www.bromite.org/), [Vanadium](https://github.com/GrapheneOS/Vanadium)
 - [Automated OTA updates](https://github.com/GrapheneOS/platform_packages_apps_Updater)
 - [MicroG](https://microg.org/)
 - Certain google apps (currently just stuff for Google Fi)
 - Easily setting various framework configuration settings such as those found [here](https://android.googlesource.com/platform/frameworks/base/+/master/core/res/res/values/config.xml)
 - Custom built kernels
 - Custom `/etc/hosts` file
 - Extracting vendor blobs from Google's images using [android-prepare-vendor](https://github.com/anestisb/android-prepare-vendor)

Future goals include:
 - Better documentation, especially for module options
 - Continuous integration / testing for various devices
 - Automating CTS (Compatibility Test Suite) like nixos tests.
 - Automatic verification of build reproducibility
 - Replacing android prebuilt toolchains with nixpkgs equivalents.
 
This has currently only been tested on crosshatch (Pixel 3 XL, my daily driver) and marlin (Pixel XL, which is now deprecated by google and no longer receiving updates).

## Quick Start
Here is a single command to build an `img` which can be flashed onto a device.
```console
$ nix-build "https://github.com/danielfullmer/robotnix/archive/master.tar.gz" \
    --arg configuration '{ device="crosshatch"; flavor="vanilla"; }' \
    -A img
```
Ensure your `/tmp` is not mounted using `tmpfs`, since the AOSP intermediate builds products are very large and will easily use all of your RAM (even if you have 32GB)!
The command above will build an image signed with `test-keys`, so definitely don't use this for anything intended to be secure.
To flash the result to your device, run `fastboot update -w <img.zip>`.

A full Android 10 build takes about 4 hours on my quad-core i7-3770 with 16GB of memory.
The default `vanilla` flavor also builds `chromium` from source for use as the system webview.
This takes approximately 6 hours on my i7-3770.
I have recently upgraded to a 3970x Threadripper with 32-cores.
This can build chromium+android in under an hour.
A user can use `--cores` option for `nix-build` to set the number of cores to
use, which can also be useful to decrease parallelism in case memory usage of
certain build steps is too large.

## Configuration and Build Options
A configuration file should be created for anything more complicated, including creating signed builds.
See my own configuration under `example.nix` for inspiration.
After creating a configuration file, generate keys for your device:

```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A generateKeysScript -o generate-keys
$ mkdir keys/crosshatch
$ cd keys/crosshatch
$ ../../generate-keys "/CN=RobotNix" # Use appropriate x509 cert fields
$ cd ../..
```

Next, build and sign your release.
There are two ways to do this.
The first option involves creating a `build-script` which does the final build steps of signing target files and creating ota/img files outside of nix:
```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A releaseScript -o release
$ ./release ./keys/crosshatch
```
One advantage of using a release script as above is that the build can take place on a different machine than the signing.
`nix-copy-closure` could be used to transfer this script and its dependencies to another computer to finish the release.

The other option is to build the final products entirely inside nix instead of using `releaseScript`
```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A img --option extra-sandbox-paths /keys=$(pwd)/keys
```
This, however, will require a nix sandbox exception so the secret keys are available to the build scripts.
To use `extra-sandbox-paths`, the user must be a `trusted-user` in `nix.conf`.

### Testing / CI / Reproducibility

All devices (Pixel 1-3(a) (XL)) have very basic checks to ensure that the android build process will at least start properly.
See `release.nix` for the set of configurations with this minimal build testing.
This check is run using `nix-build ./release.nix -A check`.
As each build takes approximately 4 hours--I only build marlin and crosshatch builds for myself.
At some point, I would love to set up a build farm and publish build products on s3 or [cachix](https://cachix.org).
This would allow an end-user to simply sign their own releases without building the entire AOSP themselves.

As of Android 10, `target-files` seem to be built reproducibly.
Further tests are needed for `img`/`ota` files.

### Emulator

To build and run an emulator with an attached vanilla system image, use (for example):
```console
$ nix-build ./default.nix --arg configuration '{device="x86"; flavor="vanilla";}' -A build.emulator
$ ./result
```

### Fetching android source files

RobotNix supports two alternative approaches for fetching source files:

- Build-time source fetching with `pkgs.fetchgit`. This is the default.
  An end user wanting to fetch sources not already included in `robotnix` would
  need to create a repo json file using `mk-repo-file.py` and update
  `source.jsonFile` to point to this file.
- Evaluation-time source fetching with `builtins.fetchGit`.
  This is more convenient for development when changing branches, as it allows use of a shared git cache.
  The end user will need to set `source.manifest.{url,rev,sha256}` and enable `source.evalTimeFetching`.
  However, with `builtins.fetchGit`, the `drv`s themselves depend on the source,
  and `nix-copy-closure` of even just the `.drv` files would require downloading the source as well.

### Additional information


Optional CCACHE stuff.
As root:
```console
# mkdir -p -m0770 /var/cache/ccache
# chown root:nixbld /var/cache/ccache
```
Set `ccache.enable = true` in configuration, and be sure to pass `/var/cache/ccache` as a sandbox exception when building.

## Notable mentions
See also: [NixDroid](https://github.com/ajs124/NixDroid), [RattlesnakeOS](https://github.com/dan-v/rattlesnakeos-stack), [aosp-build](https://github.com/hashbang/aosp-build), and [CalyxOS](https://calyxos.org/)
