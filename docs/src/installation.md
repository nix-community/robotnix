<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# Installing for the first time with (optional) verified boot

> The following instructions are specific to Pixel phones using either the
> Vanilla or GrapheneOS flavors.  For LineageOS, please refer to upstream
> device-specific documentation on how to install LineageOS builds on your
> device.

It is assumed that you have successfully built your factory image and signed it
with your own keys, either by using the `factoryImg` Nix output or by running
`releaseScript`.  Make sure that you know the location of the image and the AVB
signing key.  The instructions in this document were tested on the Google Pixel
4a (sunfish).  Other Pixel phones are similar, but please refer to [this
upstream documentation](https://source.android.com/setup/build/running).

 0. Before you can begin you have to boot the stock OS, go to "Settings / About
    phone" and tap the "Build number" field 7 times to enable the "Developer
    options" menu.  Next go to “Settings / System / Advanced / Developer
    options” and enable “OEM unlocking”.  On my device I had to insert a SIM
    card and connect to the network for that, so it looks like you have to
    connect your device with Google [at least
    once](https://grapheneos.org/install#enabling-oem-unlocking).  This is part
    of Google's so called Factory Reset Protection (FRP) for anti-theft
    protection .  However, [this
    comment](https://www.kuketz-blog.de/grapheneos-das-android-fuer-sicherheits-und-datenschutzfreaks/#comment-52681)
    on a German IT privacy blog suggests that it is sufficient to allow access
    to the captive portal such that the phone thinks it is online.

 1. First reboot into the bootloader. You can either do that physically by
    turning off your phone and then holding both the POWER and the VOLUME DOWN
    button to turn it back on, or your can connect the phone to your computer
    with USB Debugging turned on and issue
    ```console
    $ adb reboot bootloader
    ```

 2. Connect your phone to your computer and run
    ```console
    $ fastboot devices
    09071JEC217048  device
    ```

 3. Unlock the bootloader by running
    ```console
    $ fastboot flashing unlock
    ```
    Select the option to unlock the device and confirm. This step effectively
    performs a factory reset, and will remove all user data from the device.

 4. *(Strongly recommended, but technically optional)*
    Flash your custom AVB signing key using
    ```console
    $ fastboot erase avb_custom_key
    $ fastboot flash avb_custom_key avb_pkmd.bin
    $ fastboot reboot bootloader
    ```

 5. Unzip the factory image built by robotnix. To flash the image run
    ```console
    $ ./flash-all.sh
    ```
    The factory image produced by robotnix includes the bootloader and radio
    firmware in addition to the android image.  If you are certain the
    bootloader and radio are already up to date, you can instead build the
    standard `img` robotnix output, and flash the image with
    ```console
    $ fastboot -w --skip-reboot update sunfish-img-2020.11.06.04.zip
    ```
    This will erase the `userdata` partition (`-w`) and prevent the automatic
    reboot after flashing (`--skip-reboot`).

    After flashing with the `flash-all.sh` script or with `fastboot update`,
    return to the bootloader with
    ```console
    $ fastboot reboot bootloader
    ```

 6. *(Strongly recommended, but technically optional)*
    At this point you want to relock the bootloader to enable enforcement of
    the verified boot chain.
    ```console
    $ fastboot flashing lock
    ```
    This step has to be confirmed on the device.

 7. After rebooting you will be greeted with an yellow exclamation mark and a
    message like

    > Your device is loading a different operating system.
    >
    > Visit this link on another device:
    > g.co/ABH
    >
    > ID: BA135E0F

    This is expected because Android Verified Boot is designed to warn the user
    when not booting the stock OS, see
    https://source.android.com/security/verifiedboot/boot-flow.  In fact, the
    ID on the last line are the first eight characters of the fingerprint of
    your AVB key.


## Updating by sideloading OTA files
Preferably, you can update your Vanilla/GrapheneOS flavor device using true "over-the-air" mechanism provided by the `apps.updater` module with a server hosting the OTA files, as shown [here](modules/ota.md).
If this is not available, it is still possible to update by sideloading the OTA file.

> It is recommended to update using the OTA file instead of using `fastboot update` with a new `img`.
> OTA files can also contain updates to the modem / bootloader that are not included in the `img` output.
> `fastboot update` also cannot be used with a re-locked bootloader without wiping userdata.


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
