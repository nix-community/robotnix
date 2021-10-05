# Android Cuttlefish - Work in Progress

[Cuttlefish](https://source.android.com/setup/create/cuttlefish) is an android
virtual device that (in contrast to the standard android emulator) uses crosvm
along with standard virtio drivers.

Requires Linux kernel >= 4.8 (see host/lib/vm_manager/host_configuration.cpp)

First, build cuttlefish using the following commands:
```shell
$ nix-build -A cuttlefish.cvd-host_package -o cvd-host_package
$ nix-build -A cuttlefish.img -o cf_x86_phone-img.zip
```
This also has support for cross-compiling to an aarch64 target.
Use `cuttlefish_arm64` instead of `cuttlefish` in the commands above, and copy the resulting nix closure to your aarch64 device.
This has been tested working on a Pinebook Pro (RK3399 with 4GB ram).
The cuttlefish device appears to require at least 2GB memory, as it fails to boot if I decrease the available memory with the `-memory_mb` option for `launch_cvd`.

The second command above builds the cuttlefish android image, which takes quite a while.
One alternative is to just grab the cuttlefish image from android's CI system: https://ci.android.com/ .
Look for the build artifacts associated with a "userdebug" build of `aosp_cf_x86_phone`.
The file you need looks something like `aosp_cf_x86_phone-img-6981209.zip`.
Google's CI built version of `cvd-host_package`, however, will not work for us, since we have some patches to the source to fix hardcoded path issues.

Naturally, Google doesn't believe in separating read-only code from read/write state.
Until Google realizes what `PREFIX` is for, or we've patched the source, this is the easiest way to set up cuttlefish:
```shell
$ mkdir cuttlefish_tmp
$ cd cuttlefish_tmp
$ unzip ../cf_x86_phone-img.zip
$ cp -r ../cvd-host_package/* .
$ chmod -R u+w .
```

Add the following snippet to your configuration.nix:
```nix
{
  # Replace "danielrf" with your username
  users.users.danielrf.extraGroups = [ "kvm" "cvdnetwork" ];
  users.groups.cvdnetwork = {};

  boot.kernelModules = [ "vhci-hcd" "vhost_net" "vhost_vsock" ];

  # Copied from android-cuttlefish/debian/cuttlefish-common.udev
  # TODO: We can probably do better than this...
  services.udev.extraRules = ''
    ACTION=="add", KERNEL=="vhost-net", SUBSYSTEM=="misc", MODE="0660", GROUP="cvdnetwork"
    ACTION=="add", KERNEL=="vhost-vsock", SUBSYSTEM=="misc", MODE="0660", GROUP="cvdnetwork"
  '';
}
```
After adding the `cvdnetwork` group and your username to that group, you should re-login to your device.

Cuttlefish also requires some additional setup on the host, including setting up virtual networks.
Until we've made a proper NixOS module for doing this, the following hack suffices:
```
$ nix-shell -p ebtables dnsmasq
$ nix-build -A cuttlefish.src
$ sudo bash ./result/debian/cuttlefish-common.init start
```
You can tear down the virtual networks using `sudo bash ./result/debian/cuttlefish-common.init stop`.


Now, we can finally start cuttlefish:
```shell
$ cd cuttlefish_tmp
$ HOME=$PWD ./bin/launch_cvd
$ nix-shell -p tightvnc --run vncviewer localhost::6444
```
You can stop cuttlefish using `HOME=$PWD ./bin/stop_cvd`

Alternatively, you can start a web service that uses webrtc and a browser to interact with the android device.
Add `-start_webrtc=true` to the `launch_cvd` command above.
Then use a browser with the following URL: https://localhost:8443/


## TODO

We need to tranform this all into a NixOS module.
Still want to get GPU acceleration working, using either gfxstream or virgl.

More interestingly, I hope it should be possible to forward the wayland socket to the desktop somehow.
Perhaps work from spectrum-os would be useful here: https://alyssa.is/using-virtio-wl/

## Related links
 - https://android.googlesource.com/device/google/cuttlefish/
 - https://nathanchance.dev/posts/building-using-cuttlefish/
 - https://sites.google.com/junsun.net/how-to-run-cuttlefish/home#h.p_iccaGf32RvLU
