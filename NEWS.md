<!--
SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

Updates are added to this file approximately monthly, or whenever significant
changes occur which require user intervention / configuration changes.  These
are highlights since the last update, and are not meant to be an exhaustive
listing of changes. See the git commit log for additional details.


# 2021-01-05
I've started the `#robotnix` IRC channel on Freenode for a place to chat about the project, ask questions, and discuss robotnix development.

## Highlights:
- New binary cache: Now publishing certain build products on `robotnix.cachix.org`, including Pixel device kernels and Chromium variants browser / webview. (See the binary cache section of README.md)
- Updated vanilla flavor to January 2021 release
- Updated GrapheneOS flavor to January 2021 release
- Updated LineageOS flavor to 2021-12-29 (thanks @Atemu)
- Improvements to NixOS module for attestation-server (thanks @hmenke)
- MicroG updates (thanks @petabyteboy)
- Fixed `nix-instantiate` GitHub action and improved evaluation speed by importing pkgs only once in `release.nix`.
- Removed various uncessary usages of "import-from-derivation" (IFD)
- Fixed `backuptool.sh` usage by OTA files in LineageOS builds
- Fixed broken Bromite chromium / webview builds

There are no intentional backward incompatible changes since the last release.

# 2020-12-08

## Highlights:
 - Updated vanilla flavor to December 2020 release
 - Updated GrapheneOS flavor to December 2020 release
 - Updated lineageos flavor to December 2020 (thanks @Atemu)
 - Added various documentation under docs/ (thanks @hmenke)
 - Added sunfish device to attestation/auditor patches (thanks @hmenke)
 - Added remaining pixel devices to attestation/auditor patches
 - Added basic APK signature verification in Nix for prebuilt APKs (e.g. Microg / Google apks)

## Backward incompatible changes
 - Switched auditor / attestation to use device-specific keys as opposed to device-family keys

The NixOS attestation-server module option has been changed from
`services.attestation-server.deviceFamily` to
`services.attestation-server.device`.

 - Significant changes to key / certificate generation, described below.

We now use new application-specific keys and certificates for included apps
like Chromium / webview, Microg, and F-Droid, instead of relying on the
device-specific `releasekey`.  This allows us to share these keys between
multiple devices, push the same app updates to multiple devices, and remove an
ugly SELinux workaround for GrapheneOS that robotnix required.

Unfortunately, changing app keys may lose any data associated with those apps.
Fortunately, most data associated with those apps should be easy to re-create.
(Re-login to services in chromium, re-add F-Droid repos, etc.)
I hope to avoid potentially breaking changes like this in the future by getting
these changes done relatively early in the projects' life.

If you've previously generated robotnix keys, you will need to do the
following to update to the new key directory layout: Move any keys and
certificates (if they exist) beginning with `com.android` from the device
subdir (e.g.  `crosshatch`) under your `keyStorePath` to the parent directory.
The files beginning with `releasekey`, `platform`, `shared`, `media`,
`networkstack`, and `avb`/`verity` (if you have it) are device-specific, and
should remain under the device subdirectory.  For example, I ran the following
command on my machine:
 ```shell
$ mv /var/secrets/android-keys/crosshatch/com.android.* /var/secrets/android-keys/
 ```
After this, re-run `generateKeysScript` to create new application keys (e.g.
Chromium, F-Droid).
