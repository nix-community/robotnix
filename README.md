# robotnix - Build Android (AOSP) using Nix

Robotnix enables a user to build Android (AOSP) images using the Nix package manager.
AOSP projects often contain long and complicated build instructions requiring a variety of tools for fetching source code and executing the build.
This applies not only to Android itself, but also to projects which are to be included in the Android build, such as the Linux kernel, Chromium webview, MicroG, other external/prebuilt privileged apps, etc.
Robotnix orchestrates the diverse build tools across these multiple projects using Nix, inheriting its reliability and reproducibility benefits, and consequently making the build and signing process very simple for an end-user.

Robotnix includes a NixOS-style module system which allows users to easily customize various aspects of the their builds.
Some optional modules include:
 - Vanilla Android 10 AOSP support (for Pixel devices)
 - [GrapheneOS](https://grapheneos.org/) support
 - Experimental [LineageOS](https://lineageos.org/) support
 - Signed builds for verified boot (dm-verity/AVB) and re-locking the bootloader with a user-specified key
 - Apps: [F-Droid](https://f-droid.org/) (including the privileged extention for automatic installation/updating), [Auditor](https://attestation.app/about), [Seedvault Backup](https://github.com/stevesoltys/backup)
 - Browser / Webview: [Chromium](https://www.chromium.org/Home), [Bromite](https://www.bromite.org/), [Vanadium](https://github.com/GrapheneOS/Vanadium)
 - [Seamless OTA updates](https://github.com/GrapheneOS/platform_packages_apps_Updater)
 - [MicroG](https://microg.org/)
 - Certain google apps (currently just stuff for Google Fi)
 - Easily setting various framework configuration settings such as those found [here](https://android.googlesource.com/platform/frameworks/base/+/master/core/res/res/values/config.xml)
 - Custom built kernels
 - Custom `/etc/hosts` file
 - Extracting vendor blobs from Google's images using [android-prepare-vendor](https://github.com/anestisb/android-prepare-vendor)

Future goals include:
 - Support for additional flavors and devices
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
The command above will build an image signed with `test-keys`, so definitely don't use this for anything intended to be secure.
To flash the result to your device, run `fastboot update -w <img.zip>`.

## Requirements
The AOSP project requires at least 250GB free disk space as well as 16GB RAM.
A typical build  requires approximately 40GB free disk space to check out the android source, 14GB for chromium, plus some additional free space for intermediate build products.
Ensure your `/tmp` is not mounted using `tmpfs`, since the intermediate builds products are very large and will easily use all of your RAM (even if you have 32GB)!
A user can use the `--cores` option for `nix-build` to set the number of cores to
use, which can also be useful to decrease parallelism in case memory usage of
certain build steps is too large.

A full Android 10 build with chromium webview takes approximately 10 hours on my quad-core i7-3770 with 16GB of memory.
AOSP takes approximately 4 hours of that, while webview takes approximately 6 hours.
I have recently upgraded to a 3970x Threadripper with 32-cores.
This can build chromium+android in about an hour.

## Configuration and Build Options
A configuration file should be created for anything more complicated, including creating signed builds.
See my own configuration under `example.nix` for inspiration.
After creating a configuration file, generate keys for your device:

```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A generateKeysScript -o generate-keys
$ mkdir keys/crosshatch
$ cd keys/crosshatch
$ ../../generate-keys
$ cd ../..
```

Next, build and sign your release.
There are two ways to do this.
The first option involves creating a "release script" which does the final build steps of signing target files and creating ota/img files outside of nix:
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

All devices (Pixel 1-4(a) (XL)) have very basic checks to ensure that the android build process will at least start properly.
See `release.nix` for the set of configurations with this minimal build testing.
This check is run using `nix-build ./release.nix -A check`.
As each build takes approximately 4 hours--I only build marlin and crosshatch builds for myself.
At some point, I would love to set up a build farm and publish build products on s3 or [cachix](https://cachix.org).
This would allow an end-user to simply sign releases using their own keys without building the entire AOSP themselves.

As of 2020-05-17, `target_files`, `signed_target_files`, `img`, and `ota` files have all been verified to be bit-for-bit reproducible for `crosshatch` and `marlin` using the `vanilla` flavor.
Automated periodic testing of this is still desired.

One option being investigated is to have multiple independent remote builders produce unsigned target files for a number of device and flavor combinations.
An end-user could then verify that the builders produced the same unsigned target files, and finish the process by signing the target files and producing their own `img` and `ota` files.
This eliminates the requirement for an end-user to spend hours building android.

There are, however, a few places where user-specific public keys are included in the build for key pinning.
This unfortunately decreases the possibility of sharing build products between users.
The F-Droid privileged extension and Trichrome (disabled for now) are two components which have this issue.
Fixes for this are still under investigation.

### LineageOS Support
LineageOS support may be enabled by setting `flavor = "lineageos";`.
The typical LineageOS flashing process involves first producing a `boot.img` and `ota`, flashing `boot.img` with fastboot, and then flashing the `ota` in recovery mode.
The `boot.img` and `ota` targets can be built using `nix-build ... -A bootImg` or `nix-build ... -A ota`, respectively.

LineageOS support should be considered "experimental," as it does yet have the same level of support I intend to provide for `vanilla` and `grapheneos` flavors.
LineageOS source metadata may be updated irregularly in robotnix, and certain modules (such as the updater) are not guaranteed to work.
Moreover, LineageOS does not appear to provide the same level of security as even the vanilla flavor, with dm-verity/AVB often disabled, `userdebug` as the default variant, and vendor files with unclear origin.
LineageOS support is still valuable to include as it extends preliminary support to a much wider variety of devices, and provides the base that many other Android ROMs use to customize.
Contributions and fixes from LineageOS users are especially welcome!

### Emulator

To build and run an emulator with an attached vanilla system image, use (for example):
```console
$ nix-build ./default.nix --arg configuration '{device="x86"; flavor="vanilla";}' -A build.emulator
$ ./result
```

### Fetching android source files

Robotnix supports two alternative approaches for fetching source files:

- Build-time source fetching with `pkgs.fetchgit`. This is the default.
  An end user wanting to fetch sources not already included in `robotnix` would
  need to create a repo json file using `mk-repo-file.py` and set
  `source.dirs = lib.importJSON ./example.json;`
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
# echo max_size = 100G > /var/cache/ccache/ccache.conf
```
Set `ccache.enable = true` in configuration, and be sure to pass `/var/cache/ccache` as a sandbox exception when building.

## Notable mentions
See also: [NixDroid](https://github.com/ajs124/NixDroid), [RattlesnakeOS](https://github.com/dan-v/rattlesnakeos-stack), [aosp-build](https://github.com/hashbang/aosp-build), and [CalyxOS](https://calyxos.org/)
