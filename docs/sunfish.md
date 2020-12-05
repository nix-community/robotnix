# Installing for the first time and verified boot

It is assumed that you have successfully built your image and signed it with
your own keys.  Make sure that you know the location of the image and the AVB
signing key.

 0. Before you can begin you have to boot the stock OS and go to “Settings /
    System / Advanced / Developer options” and enable “OEM unlocking”.  On my
    device I had to insert a SIM card and connect to the network for that, so
    it looks like you have to connect your device with Google at least once.

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

 3. If you 

 3. First flash your custom AVB signing key using
    ```console
    $ fastboot erase avb_custom_key 
    $ fastboot flash avb_custom_key avb_pkmd.bin
    $ fastboot reboot bootloader
    ```

 4. To flash you image use
    ```console
    $ fastboot -w --skip-reboot update sunfish-img-2020.11.06.04.zip
    $ fastboot reboot bootloader
    ```
    This will erase the `userdata` partition (`-w`) and prevent the automatic
    reboot after flashing (`--skip-reboot`). Instead it reboots back into the
    bootloader from where the user can then manually trigger the reboot using
    ```console
    $ fastboot reboot
    ```

 5. At this point you want to relock the bootloader to enable the verified boot
    chain.
    ```
    $ fastboot flashing lock
    ```
    This step has to be confirmed on the device.

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
    $ adb sideload sunfish-ota_update-2020.11.26.17.zip
    ```
    The sideload might terminate at 94% with “adb: failed to read command:
    Success”.  This is not an error even though it is not obvious, see also
    [here](https://np.reddit.com/r/LineageOS/comments/dt2et4/adb_failed_to_read_command_success/f6u352m).

 7. Once finished and the device doesn't automatically reboot just select
    reboot from the menu and confirm.
