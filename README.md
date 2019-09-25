# NixDroid

This is a fork of the original NixDroid, focusing on customized vanilla-ish AOSP targeting Pixel devices.
Some features include:
 - Uses a NixOS-style module system for configuring the build
 - Signing builds for verified boot (dm-verity/AVB) and re-locking the bootloader
 - Automated OTA updates
 - Partial GrapheneOS support (currently doesn't build Vanadium, the chromium fork)
 - Preliminary support for Android 10

Further goals include:
 - Better documentation, especially for module options
 - Reproducible builds
 - Continuous integration / testing

This has currently only been tested on marlin (Pixel XL) and crosshatch (Pixel 3 XL), but should support all Pixel devices with (hopefully) minor changes.

A one line `.img` build:
```console
$ nix-build "https://github.com/danielfullmer/NixDroid/archive/vanilla.tar.gz" --arg configuration '{device="marlin";}' -A config.build.factoryImg
```
this will make generate an image signed with `test-keys`, so don't use it for anything other than testing.

A configuration file should be created for anything more complicated, including creating signed builds.
See `example.nix`, `marlin.nix`, and `crosshatch.nix` for inspiration.

Generate keys to sign your build:

```console
$ nix-build ./default.nix --arg configuration ./marlin.nix -A config.build.generateKeysScript -o generate-keys
$ mkdir keys/marlin
$ cd keys/marlin
$ ../generate-keys "/CN=NixDroid" # Use appropriate x509 cert fields
$ cd ../..
```

Build and sign your release:

```console
$ nix-build ./default.nix --arg configuration ./marlin.nix -A config.build.releaseScript -o release
$ ./release ./keys/marlin
```

One advantage of using a release script is that the build can take place on a different machine than the signing.
`nix-copy-closure` could be used to transfer this script and its dependencies to another computer to finish the release.

One alternative to using the `releaseScript` is to build the final products inside nix.
This, however, will require a nix sandbox exception so the secret keys are available to the build scripts.

```console
$ nix-build ./default.nix --arg configuration ./marlin.nix -A config.build.img --option extra-sandbox-paths /keys=$(pwd)/keys
```
To use `extra-sandbox-paths`, the user must be a `trusted-user` in `nix.conf`.
The root user is always trusted, however, running `sudo nix-build ...` would use root's git cache for `builtins.fetchgit`, which would effectively re-download the source again.

### Additional information:

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
