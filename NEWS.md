<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer
SPDX-License-Identifier: MIT
-->

Updates are added to this file approximately monthly, or whenever significant
changes occur which require user intervention / configuration changes.  These
are highlights since the last update, and are not meant to be an exhaustive
listing of changes. See the git commit log for additional details.

# 2021-11-07
- Switch to Trichrome by default for chromium/webview variants
- Updated vanilla flavor to 2021110203
- Updated GrapheneOS flavor to 2021110617
- Updated Chromium / Vanadium to 95.0.4638.74, Bromite to 95.0.4638.78
- Added Android 12 support for `pixel.activeEdge` module
- Various fixes for vanilla flavor

## Backward-incompatible changes
- Pixel 3 (XL) devices (`crosshatch` and `blueline`) are no longer receiving monthly vendor updates from Google.

# 2021-10-24
## Highlights:
- Android 12 support for `vanilla` and `grapheneos` flavors. Set default `androidVersion = 12`.
- New LineageOS-flavored updater module [PR #90](https://github.com/danielfullmer/robotnix/pull/90) (thanks @ajs124)
- New Active Edge module for Pixel devices [PR #125](https://github.com/danielfullmer/robotnix/pull/125) (thanks @zhaofengli)
- New `pixel.useUpstreamDriverBinaries` option to use binaries from [here](https://developers.google.com/android/drivers) instead of android-prepare-vendor. (Only recommended for testing)
- Updated vanilla flavor to SP1A.210812
- Updated GrapheneOS flavor to 2021102300
- Updated LineageOS flavor to 2021102406
- Updated Chromium / Vanadium to 95.0.4638.50, Bromite to 94.0.4606.102
- Updated Seedvault to 11-2.3 tag for Android 11, 2021-10-23 for Android 12
- Added microG patches for Android 12
- Updated Updater to 2021-10-22
- Refactor and separate kernel building for vanilla and GrapheneOS
- Now set default `buildDateTime` automatically based on maximal `source.dirs.<relpath>.dateTime`, as fallback in case there is not a better way to set it.

There are no intentional backward incompatible changes since the last release.

# 2021-09-09
## Highlights:
- Added support for new device, "barbet" (Pixel 5a), on vanilla and GrapheneOS flavors.
- Updated vanilla flavor to RQ3A.210905
- Updated GrapheneOS flavor to 2021090819
- Updated LineageOS flavor to 2021.08.10.22
- Updated Auditor / AttestationServer to 29 / 2021-09-08
- Updated Chromium / Vanadium to 93.0.4577.62, Bromite to 92.0.4515.134
- Updated Updater to 2021-08-25
- Updated MicroG to 0.2.22.212658
- Installation documentation improvements (thanks @mschwaig)
- Significant code-quality improvements (enabled tests, various checks) to update scripts
- Added `--cache-search-path` and `--local_manifest` options to `mk_repo_file.py`

There are no intentional backward incompatible changes since the last release.

We have (hopefully temporarily) switched back to prebuilt kernels for redfin and related devices (bramble and barbet) in the vanilla flavor.
Re-adding support for building these kernels in robotnix will likely require resolving [#116](https://github.com/danielfullmer/robotnix/issues/116).

# 2021-08-03
## Highlights:
- Updated vanilla flavor to RQ3A.210805
- Updated vanilla beta (Android 12) to android-s-beta-3
- Updated GrapheneOS flavor to 2021.08.03.03
- Updated Lineageos flavor to 2021.07.12.17
- Added ROBOTNIX_GIT_MIRRORS environment variable (See [documentation](https://docs.robotnix.org/development.html#git-mirrors))
- Updated Chromium / Vanadium to 92.0.4515.115, Bromite to 92.0.4515.125
- Updated Updater to 2021-08-02

There are no intentional backward incompatible changes since the last release.

Between commits on Aug 2-3 there was brief period where the robotnix would not correctly include the Update package for the GrapheneOS flavor.
If you have already updated your device with a build produced during this interval, and you don't see "System updates" under "Settings", you can still update your device by sideloading, [instructions here](https://docs.robotnix.org/installation.html#updating-by-sideloading-ota-files).

# 2021-07-07
## Highlights:
- Added experimental Anbox flavor (thanks @samueldr) (See initial docs [here](https://docs.robotnix.org/modules/flavors.html#anbox))
- Updated vanilla flavor to RQ3A.210705
- Updated GrapheneOS flavor to 2021.07.07.19
- Updated LineageOS flavor to 2021.06.21.20 (thanks @Kranzes)
- Updated F-Droid to 1.12.1, F-Droid privileged extension to 0.2.12
- Updated MicroG to 0.2.21.212158
- Updated Chromium / Vanadium to 91.0.4472.134, Bromite to 91.0.4472.102

There are no intentional backward incompatible changes since the last release.

# 2021-06-09
## Highlights:
- Updated LineageOS flavor from 17.1 to 18.1 (up-to-date as of 2021-05-22) [PR #96](https://github.com/danielfullmer/robotnix/pull/96) (thanks @hmenke).
- Updated vanilla flavor to RQ3A.210605
- Updated GrapheneOS flavor to 2021.06.08.06
- Updated Auditor / AttestationServer to 27 / 2021-05-19
- Updated Chromium to 91.0.4472.88
- Updated MicroG to 0.2.19.211515
- Fixed building outside Nix sandbox by introducing `signing.buildTimeKeyStorePath` option.

## Backward-incompatible changes
- Renamed `keyStorePath` to `signing.keyStorePath`.
- Removed flaky `google.*` module options.  Moved to `robotnixModules.google` flake output under [danielfullmer/robotnix-personal](https://github.com/danielfullmer/robotnix-personal).

# 2021-05-04
## Highlights:
- Updated vanilla flavor to RQ2A.210505
- Updated GrapheneOS to 2021.05.04.01
- Updated Chromium / Vanadium to 90.0.4430.91, and updated Bromite to 90.0.4430.101

There are no intentional backward incompatible changes since the last release.


# 2021-04-18
## Highlights:
- New documentation located at [docs.robotnix.org](https://docs.robotnix.org) [PR #88](https://github.com/danielfullmer/robotnix/pull/88), including [autogenerated docs](https://docs.robotnix.org/options.html) for robotnix configuration options.
- Updated vanilla flavor to RQ2A.210405.005
- Updated GrapheneOS flavor to 2021.04.16.04
- Updated Chromium / Vanadium to 89.0.4389.90, and update Bromite to 89.0.4389.100
- Updated MicroG to 0.2.18.204714
- Updated Auditor / AttestationServer to 26 /  2021-03-19.
- Updated Seedvault to 11-1.1

## Backward-incompatible changes
- Renamed `kernel.useCustom` to `kernel.enable`.

# 2021-03-02
## Highlights:
- Added support for Pixel 5 (redfin) and Pixel 4a (5g) (bramble) [PR #79](https://github.com/danielfullmer/robotnix/pull/79)
- Added support for building as a nix flake [PR #85](https://github.com/danielfullmer/robotnix/pull/85) (with help from @hmenke)
  For reference, I've also migrated my [personal config](https://github.com/danielfullmer/robotnix-personal) to flakes.
- LineageOS now uses robotnix-built webview by default since upstream force-pushes to the prebuilt webview repository, breaking reproducibility.
- Added Android 12 preview, tested working for `x86_64` in emulator
- Added SPDX license headers to various files (thanks @lnceballosz)
- Updated vanilla flavor to RQ2A.210305.006
- Updated GrapheneOS flavor to 2021.03.02.10
- Updated Chromium / Vanadium to 88.0.4324.181, and updated Bromite to 88.0.4324.207
- Updated Auditor / AttestationServer to latest versions to support redfin/bramble
- Updated Seedvault backup app to 2021-01-19

## Backward-incompatible changes
- The `resourceTypeOverrides` option was replaced with `resources.<package>.<name>.type`.

# 2021-02-02
## Highlights:
- Updated vanilla flavor to RQ1A.210205.004
- Updated GrapheneOS flavor to 2021.02.02.09
- Chromium / Bromite / Vanadium updated to 88.0.4324.141
- F-Droid updated to 1.11
- MicroG updated to 2.0.17.204714 (thanks @petabyteboy)
- Added basic test for attestation server
- Fixed attestation server module not starting properly on boot (thanks @hmenke)

There are no intentional backward incompatible changes since the last release.

# 2021-01-05
I've started the `#robotnix` IRC channel on Freenode for a place to chat about the project, ask questions, and discuss robotnix development.

## Highlights:
- New binary cache: Now publishing certain build products on `robotnix.cachix.org`, including Pixel device kernels and Chromium variants browser / webview. (See the binary cache section of README.md)
- Updated vanilla flavor to January 2021 release
- Updated GrapheneOS flavor to January 2021 release
- Updated LineageOS flavor to 2020-12-29 (thanks @Atemu)
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
