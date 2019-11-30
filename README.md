# NixDroid

This is a fork of the ajs124's NixDroid, focusing on customized vanilla-ish AOSP targeting Pixel devices.
Some features include:
 - A NixOS-style module system for customizing various aspects of the build
 - Signed builds for verified boot (dm-verity/AVB) and re-locking the bootloader
 - Partial GrapheneOS support (currently doesn't build Vanadium, the chromium fork)
 - Android 10 Support
 
Some optional nixos-style modules include:
 - Apps: [F-Droid](https://f-droid.org/) (including the privileged extention for automatic installation/updating), [Auditor](https://attestation.app/about), [Backup](https://github.com/stevesoltys/backup)
 - [Automated OTA updates](https://github.com/GrapheneOS/platform_packages_apps_Updater)
 - [MicroG](https://microg.org/)
 - Certain google apps (currently just stuff for Google Fi)
 - Easily setting various framework configuration settings such as those found in [here](https://android.googlesource.com/platform/frameworks/base/+/master/core/res/res/values/config.xml)
 - Custom built kernels
 - Setting a custom /etc/hosts file
 - Extracting vendor blobs from Google's images using [android-prepare-vendor](https://github.com/anestisb/android-prepare-vendor)

Further goals include:
 - Better documentation, especially for module options
 - Continuous integration / testing for various devices
 - Automating CTS (Compatibility Test Suite) like nixos tests.
 - Automatic verification of build reproducibility
 
This has currently only been tested on crosshatch (Pixel 3 XL, my daily driver) and marlin (Pixel XL, which is now deprecated by google and no longer receiving updates).

## Build Instructions
A one line `.img` build:
```console
$ nix-build "https://github.com/danielfullmer/NixDroid/archive/vanilla.tar.gz" --arg configuration '{device="crosshatch";}' -A factoryImg
```
this will make generate an image signed with `test-keys`, so don't use it for anything other than testing.

A configuration file should be created for anything more complicated, including creating signed builds.
See `example.nix` and `crosshatch.nix` for inspiration.

After creating a configuration file, generate keys with which to sign your build:

```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A generateKeysScript -o generate-keys
$ mkdir keys/crosshatch
$ cd keys/crosshatch
$ ../generate-keys "/CN=NixDroid" # Use appropriate x509 cert fields
$ cd ../..
```

Next, build and sign your release.
There are two ways to create a build.
One involves creating a `build-script` which does the final build steps of signing target files and creating ota/img files outside of nix:
```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A releaseScript -o release
$ ./release ./keys/crosshatch
```
A full android 10 build takes about 4 hours on my i7-3770 with 16GB of memory.
One may use the `--cores` option for `nix-build` to set the number of cores to use.

One advantage of using a release script as above is that the build can take place on a different machine than the signing.
`nix-copy-closure` could be used to transfer this script and its dependencies to another computer to finish the release.

The other way to create a build is to build the final products entirely inside nix instead of using `releaseScript`
```console
$ nix-build ./default.nix --arg configuration ./crosshatch.nix -A img --option extra-sandbox-paths /keys=$(pwd)/keys
```
This, however, will require a nix sandbox exception so the secret keys are available to the build scripts.
To use `extra-sandbox-paths`, the user must be a `trusted-user` in `nix.conf`.
The root user is always trusted, however, running `sudo nix-build ...` would use root's git cache for `builtins.fetchgit`, which would effectively re-download the source again.

### Speeding up the build
The default mode of operation involves copying the source files multiple times.
Once from the nix's git cache into the nix store, and again during every build into a temporary location.
Since the AOSP source tree is very large--this can take a significant amount of time and is especially painful when tweaking configuration files.
There are patches under `misc/nix.nix` to speed some of this up using reflink (if your filesystem supports that).
Mine does not, so I looked for another soluation.

The most recent solution for speeding this up relies on user namespaces + bind mounts + bindfs, to simply bind mount the source from /nix/store into the temporary location while building.
Android 10 builds should work fine with read-only source trees.
However, it sometimes copies files from the source and uses the original permissions set on those files--which does not work for /nix/store which does not have user-write permissions on its files.
So, a fuse filesystem called "bindfs" used in addition to bind mounts to fake the `u+w` permission on the source files.
The nix sandbox does not normally allow access to `/dev/fuse`, so this mode is only enabled if an additional sandbox exception is made for `/dev/fuse` with `--extra-sandbox-paths "/dev/fuse?"`

### Testing / CI / Reproducibility

All devices (Pixel 1-3(a) (XL)) have very basic checks to ensure that the android build process will at least start properly.
See `test.nix` for the set of configurations with this minimal build testing.
As each build takes approximately 4 hours--I only build marlin and crosshatch builds for myself.
At some point, I would love to set up a build farm and publish build products on s3 or [cachix](https://cachix.org).
This would allow an end-user to simply sign their own releases without building the entire AOSP themselves.

As of Android 10, `target-files` seem to be built reproducibly.
Further tests are needed for `img`/`ota` files.

### Additional information

```console
# To easily build NixDroid outside of nix for debugging
$ nix-shell ... -A config.build.android
$ source $debugUnpackScript       # should just create files under nixdroid/
# Apply any patches in $patches
$ runHook postPatch

$ export TMPDIR=/tmp
$ export OUT_DIR_COMMON_BASE=/mnt/media/out
$ source build/envsetup.sh
$ choosecombo debug aosp_x86_64 userdebug
$ make target-files-package

# sign target files
# ota_from_target_files also needs xxd (toybox works)
```

### Optional CCACHE stuff:
As root:
```console
# mkdir -p -m0770 /var/cache/ccache
# chown root:nixbld /var/cache/ccache
```
Set `ccache.enable = true` in configuration, and be sure to pass `/var/cache/ccache` as sandbox exception when building.
