<!--
SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# Installing for the first time and with verified boot

It is assumed that you have successfully built your factory image and signed it
with your own keys, either by using the `factoryImg` Nix output or by running
`releaseScript`.  Make sure that you know the location of the image and the AVB
signing key.  The instructions in this document were tested on the Google Pixel
4a (sunfish).  Other Pixel phones are similar, but please refer to
https://source.android.com/setup/build/running

 0. Before you can begin you have to boot the stock OS, go to "Settings / About
    phone" and tap the "Build number" field 7 times to enable the "Developer
    options" menu.  Next go to “Settings / System / Advanced / Developer
    options” and enable “OEM unlocking”.  On my device I had to insert a SIM
    card and connect to the network for that, so it looks like you have to
    connect your device with Google at least once.  This is part of Google's so
    called Factory Reset Protection (FRP) for anti-theft protection
    (https://grapheneos.org/install#enabling-oem-unlocking).  However, [this
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
    Select the option to unlock the device and confirm. This step effectively performs a factory reset, and will remove all user data from the device.

 4. Flash your custom AVB signing key using
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

 6. At this point you want to relock the bootloader to enable the verified boot
    chain.
    ```console
    $ fastboot flashing lock
    ```
    This step has to be confirmed on the device.

 7. After rebooting you will be greeted with an orange exclamation mark and a
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
