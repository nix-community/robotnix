# Building OTA updates

Robotnix includes a convenient target which will build a directory containing
OTA files ready to be sideloaded or served over the web.  To generate the OTA
directory, build the `otaDir` attribute (here for sunfish):
```console
$ nix-build --arg configuration ./sunfish.nix -A otaDir -o ota-dir
```
The directory structure will look similar to this (arrows indicate symbolic
links) with possibly different timestamps and hashes of course:
```console
$ tree -l ota-dir
├── sunfish-ota_update-2021.02.06.16.zip -> /nix/store/wwr49all6x868f0mdl11369ybfwyir0f-sunfish-ota_update-2021.02.06.16.zip
├── sunfish-stable -> /nix/store/c1rp46m9spncanacglqs5mxk6znfs44s-sunfish-stable
└── sunfish-target_files-2021.02.06.16.zip -> /nix/store/8ys21rzjqhi2055d7bd4iwa15fv1m446-sunfish-signed_target_files-2021.02.06.16.zip
```
The file `sunfish-ota_update-2021.02.06.16.zip` can be sideloaded with adb as
described in the next section.

# Installing OTA updates with adb

To install OTA updates you have to put the device in sideload-mode.

 1. First reboot into the bootloader. You can either do that physically by
    turning off your phone and then holding both the POWER and the VOLUME DOWN
    button to turn it back on, or your can connect the phone to your computer
    with USB Debugging turned on and issue
    ```console
    $ adb reboot recovery
    ```
    If you used the physical method, at the bootloader prompt use the VOLUME
    keys to select “Recovery Mode” and confirm with the POWER button.

 3. Now the recovery mode should have started and you should see a dead robot
    with a read exclamation mark on top. If you see “No command” on the screen,
    press and hold POWER. While holding POWER, press VOLUME UP and release
    both.

 4. At the recovery menu use the VOLUME keys to select “Apply update from ADB”
    and use POWER to confirm.

 5. Connect your phone to your computer and run
    ```console
    $ adb devices
    List of devices attached
    09071JEC217048  sideload
    ```
    The output should show that the device is in sideload mode.

 6. Now you can proceed to sideload the new update.
    ```console
    $ adb sideload sunfish-ota_update-2021.02.06.16.zip
    ```
    The sideload might terminate at 94% with “adb: failed to read command:
    Success”.  This is not an error even though it is not obvious, see also
    [here](https://np.reddit.com/r/LineageOS/comments/dt2et4/adb_failed_to_read_command_success/f6u352m).

 7. Once finished and the device doesn't automatically reboot just select
    reboot from the menu and confirm.

# Actually serving OTA updates over the air

> *Note:* These instructions were only tested with the GrapheneOS flavor.  This
> method does not work for the LineageOS flavor because it uses its own updater.

Essentially this boils down to just serving the `otaDir` build output on the
web, e.g. with nginx.  To receive OTA updates on the device, enable the updater
and point it to the domain and possibly subdirectory that you will be serving
OTA updates from:
```nix
# device configuration
{
  apps = {
    updater.enable = true;
    updater.url = "https://example.com/android/";
  };
}
```
On the server, it is as easy as serving a directory at the required
endpoint:
```nix
# NixOS server configuration
{
  services.nginx.enable = true;
  systemd.services.nginx.serviceConfig.ReadOnlyPaths = [ "/var/www" ];
  services.nginx.virtualHosts."example.com" = {
    forceSSL = true;
    enableACME = true;
    locations."/android/" = {
      root = "/var/www";
      tryFiles = "$uri $uri/ =404";
    };
  };
}
```
The directory simply contains symlinks to the store paths that were contained in
the `otaDir` output that was built earlier.  I choose to just copy the result
symlink to `/var/www/android`.
```console
$ cp --no-dereference ota-dir /var/www/android
$ tree -l /var/www
/var/www
└── android -> /nix/store/dbjcl9lwn6xif9c0fy8d2wwpn9zi4hw4-sunfish-otaDir                   
    ├── sunfish-ota_update-2021.02.06.16.zip -> /nix/store/wwr49all6x868f0mdl11369ybfwyir0f-sunfish-ota_update-2021.02.06.16.zip
    ├── sunfish-stable -> /nix/store/c1rp46m9spncanacglqs5mxk6znfs44s-sunfish-stable                             
    └── sunfish-target_files-2021.02.06.16.zip -> /nix/store/8ys21rzjqhi2055d7bd4iwa15fv1m446-sunfish-signed_target_files-2021.02.06.16.zip
```
Of course, this doesn't have to be located at `/var/www` and it's totally
possible to integrate updating of the OTA directory into your other robotnix
build automation.  In this case it is as easy as updating the `/var/www/android`
symlink with the new build output.

Here it was assumed that Robotnix was built on the same machine that you will
serve the OTA from.  If that is not the case you can conveniently copy the
closure to a remote host using `nix copy` as in
``` console
$ nix copy --to ssh://user@example.com ./ota-dir
```
Don't forget to add the store path of the `ota-dir` as a garbage collector root
on the remote machine or it might be collected in the next sweep.
