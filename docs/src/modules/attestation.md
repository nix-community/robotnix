<!--
SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# Set up remote attestation

GrapheneOS has created an Auditor app, as well as a Remote Attestation service, which "use hardware-based security features to validate the identity of a device along with authenticity and integrity of the operating system.
See the [About page](https://attestation.app/about) for additional details.

Robotnix patches the Auditor app and Remote Attestation service to allow for using the user-created keys.
This makes the app (and also the Android build itself) depend on information derived from the device signing key(s).
The current code in robotnix only works with a single custom device type.
E.g. the attestation service cannot handle robotnix-customized versions of both `crosshatch` and `sunfish`.
Future improvements may allow the Auditor app and attestation service to work with multiple custom robotnix devices.

## Android side

 1. You can enable the Auditor app in the configuration:
    ```nix
    {
      signing.enable = true;
      signing.keyStorePath = "/dev/shm/android-keys";

      apps = {
        auditor.enable = true;
        auditor.domain = "attestation.example.com";
      };
    }
    ```
    You also need to have signing enabled during build time because the Auditor
    app needs to know its own signing key during build.

 2. That's it from the Android side.  Note that the custom Auditor app will be
    named “Robotnix Auditor”.  When you build GrapheneOS the normal Auditor app
    will still be there in case you'd like to.

## Server side

 1. Before we begin we have to obtain the fingerprint of the custom Auditor app
    and the AVB fingerprint.  To get the Auditor app fingerprint, we simply use
    OpenSSL to extract the fingerprint of the signing certificate:
    ```console
    $ openssl x509 -noout -fingerprint -sha256 -in keys/auditor.x509.pem | awk -F '=' '{gsub(/:/,""); print $2}'
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    ```
    The AVB fingerprint is a bit more tricky.  I own a Pixel 4a (sunfish) and
    on this device the AVB fingerprint is simply the SHA256 hash of the AVB
    key, but this is not the case on other devices.  Check the Auditor source
    code for details.
    ```console
    $ sha256sum keys/sunfish/avb_pkmd.bin | awk '{print toupper($1)}'
    BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
    ```

 2. Now you can import robotnix in your NixOS configuration with the
    aforementioned fingerprints.
    ```nix
    { config, lib, pkgs, ... }:
    {
      imports = [
        ((builtins.fetchTarball {
          name = "robotnix";
          # Replace the git revision and sha256 with ones referring to a recent commit
          url =
            "https://github.com/danielfullmer/robotnix/archive/61b91d145f0b08cf0d4d73fb1d7ba74b9899b788.zip";
          sha256 = "1dihmdw5w891jq2fm7mcx30ydjjd33ggbb60898841x5pzjx6ynv";
        }) + "/nixos")
      ];

      services.attestation-server = {
        enable = true;
        domain = "attestation.example.com";
        device = "sunfish";
        signatureFingerprint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        avbFingerprint = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
        #disableAccountCreation = true; # optionally uncomment after creating your account
        #nginx.enableACME = true; # optionally uncomment if you want to use Let's Encrypt for HTTPS
      };
    }
    ```

 3. Register and optionally disable account creation.  The start the “Robotnix
    Auditor” app on your phone and open the menu (three dots).  Choose “Enable
    remote verification” and scan the QR code on your attestation server.

 4. The attestation server keeps its state in `/var/lib/private/attestation`.
    **Make periodic backups!**
