<!--
SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

> [!IMPORTANT]
> This project is *not* under active maintenance and arguably has not been for a couple of years.  
> Development is sporadic and is not currently able to keep up with upstream development.

At this point, Robotnix is not ready for daily use. Treat it as in-development alpha software.

The [status section](#Status) contains more detailed information on which components are expected to work.

# robotnix - Build Android (AOSP) using Nix

Robotnix enables a user to easily and reliably build Android (AOSP) images using the Nix package manager / build tool.

## Quick Start
Here is a single command to build an `img` which can be flashed onto a Pixel 3 XL (`crosshatch`).
```console
$ nix-build "https://github.com/danielfullmer/robotnix/archive/master.tar.gz" \
    --arg configuration '{ device="crosshatch"; flavor="vanilla"; }' \
    -A img
```
The command above will build an image signed with publicly known `test-keys`, so definitely don't use this for anything intended to be secure.
To flash the result to your device, run `fastboot update -w <img.zip>`.

## Motivation
Android projects often contain long and complicated build instructions requiring a variety of tools for fetching source code and executing the build.
This applies not only to Android itself, but also to projects included in the Android build, such as the Linux kernel, Chromium webview, MicroG, other external/prebuilt privileged apps, etc.
Robotnix orchestrates the diverse build systems across these multiple projects using Nix, inheriting its reliability and reproducibility benefits, and consequently making the build and signing process very simple for an end-user.

Robotnix includes a NixOS-style module system which allows users to easily customize various aspects of the their builds.
Some optional modules include:
 - Vanilla Android 12 AOSP support (for Pixel devices)
 - [GrapheneOS](https://grapheneos.org/) support
 - Experimental [LineageOS](https://lineageos.org/) support
 - Signed builds for verified boot (dm-verity/AVB) and re-locking the bootloader with a user-specified key
 - Apps: [F-Droid](https://f-droid.org/) (including the privileged extension for automatic installation/updating), [Auditor](https://attestation.app/about), [Seedvault Backup](https://github.com/stevesoltys/backup)
 - Browser / Webview: [Chromium](https://www.chromium.org/Home), [Bromite](https://www.bromite.org/), [Vanadium](https://github.com/GrapheneOS/Vanadium)
 - [Seamless OTA updates](https://github.com/GrapheneOS/platform_packages_apps_Updater)
 - [MicroG](https://microg.org/)
 - Easily setting various framework configuration settings such as those found [here](https://android.googlesource.com/platform/frameworks/base/+/master/core/res/res/values/config.xml)
 - Custom built kernels
 - Custom `/etc/hosts` file
 - Extracting vendor blobs from Google's images using [android-prepare-vendor](https://github.com/anestisb/android-prepare-vendor)

## Documentation
More detailed robotnix documentation is available at [https://docs.robotnix.org](https://docs.robotnix.org), and should be consulted before use.

Robotnix was presented at Nixcon 2020, and a recording of the talk is available [here](https://youtu.be/7sQa04olUA0?t=22314).
Slides for the talk are also available [here](https://cfp.nixcon.org/media/robotnix-nixcon2020-final.pdf).

## Requirements
The AOSP project recommends at least 250GB free disk space as well as 16GB RAM. (Certain device kernels which use LTO+CFI may require even more memory)
A typical build requires approximately 45GB free disk space to check out the android source, ~14GB for chromium, plus ~100GB of additional free space for intermediate build products.
By default, Nix uses `/tmp` to store these intermediate build products, so ensure your `/tmp` is not mounted using `tmpfs`, since the intermediate builds products are very large and will easily use all of your RAM (even if you have 32GB)!
A user can use the `--cores` option for `nix-build` to set the number of cores to use, which can also be useful to decrease parallelism in case memory usage of certain build steps is too large.

Robotnix also requires support for user namespaces (`CONFIG_USER_NS` Linux kernel option).
Currently, using the "signing inside Nix with a sandbox exception" feature also requires a Nix daemon with the sandbox support enabled.
This feature is currently not supported inside Docker for this reason.

A full Android 10 build with Chromium webview takes approximately 10 hours on my quad-core i7-3770 with 16GB of memory.
AOSP takes approximately 4 hours of that, while webview takes approximately 6 hours.
I have recently upgraded to a 3970x Threadripper with 32-cores.
This can build chromium+android in about an hour.

## Community
The `#robotnix:nixos.org` channel on Matrix is available for a place to chat about the project, ask questions, and discuss robotnix development.
You can easily join the channel using the Element web client via [this link](https://app.element.io/#/room/#robotnix:nixos.org).

## Status

This table documents the current status of Robotnix' components.

Note that the "Maintained" column reflects whether there has been an effort to maintain the component in the past few years. "Maintained" components can be expected to work and not have fallen into disrepair but, until this project is under active maintenance again, no component can be expected to be reasonably up to date.

This table primarily exists to show the opposite: which components cannot be expected to work or might even be removed in the future; to set the right expectations.

| Component                 | Maintained | Subject to removal             | People knowledgeable |
|---------------------------|------------|--------------------------------|----------------------|
| Android versions          | Yes        | -                              | @Atemu               |
| dependencies (Nixpkgs)    | Yes        | -                              | @Atemu @eyJhb        |
| General code organisation | No         | -                              | @Atemu               |
| lineageos                 | Yes        | No                             | @Atemu               |
| vanilla                   | No         | @Atemu might pick it up        | -                    |
| graphene                  | No         | @Atemu might pick it up        | -                    |
| waydroid                  | No         | Maybe                          | -                    |
| anbox                     | No         | Yes (upstream is dead)         | -                    |
| lineageos updater         | Yes        | No                             | @Atemu               |
| F-droid                   | Yes        | No                             | @Atemu @eyJhb        |
| µG                        | Yes        | No                             | @Atemu               |
| Webview                   | No         | No                             | -                    |
| Kernels                   | No         | No                             | -                    |
| Pixel vendor blobs        | No         | No                             | -                    |
| Signing                   | No         | No                             | -                    |
| Framework configuration   | No         | No                             | -                    |
| Emulator                  | No         | No                             | -                    |
| Hosts-file                | No         | No                             | -                    |
| OTA Updater               | No         | Yes                            | -                    |
| Seedvault                 | No         | Yes                            | -                    |
| Auditor                   | No         | Yes                            | -                    |
| Chromium source build     | No         | Yes (or replaced by prebuilts) | -                    |

## License information
This project is available as open source under the terms of MIT license. However, for accurate information, please check individual files.
