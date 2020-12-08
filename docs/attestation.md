# Set up remote attestation

## Android side

 1. Before you can enable the Auditor app in your configuration you have to
    generate a signing key.  There is currently no script generated for this, but
    it's easy enough to do using the `generateKeysScript` target.
    ```console
    $ nix-build \
    	--arg configuration ./sunfish.nix \
    	-A generateKeysScript \
    	-o generate-keys
    $ cp -L generate-keys auditor-keys
    ```
    Then delete the line with the assignment of the `KEYS`variable and replace it
    with `KEYS=( auditor )`.  I have also changed the common name of the
    certificate to `Robotnix auditor` because it is not device dependent.  The
    resulting script should look something like this (with potentially different
    hashes of course):
    ```bash
    #!/nix/store/2jysm3dfsgby5sw5jgj43qjrb5v79ms9-bash-4.4-p23/bin/bash
    set -euo pipefail

    export PATH=/nix/store/q0ajpzppqfrlbzbddbbzv1w6vfzydhk5-openssl-1.1.1g-bin/bin:/nix/store/8plhh65p17qlyp7k74vaiisyrhg15hwr-android-key-tools/bin:$PATH

    KEYS=( auditor )

    for key in "${KEYS[@]}"; do
      if [[ ! -e "$key".pk8 ]]; then
        echo "Generating $key key"
        # make_key exits with unsuccessful code 1 instead of 0
        make_key "$key" "/CN=Robotnix auditor/" && exit 1
      else
        echo "Skipping generating $key since it is already exists"
      fi
    done
    ```
    Run the script to generate the keys:
    ```bash
    $ cd keys/
    $ bash ../auditor-keys
    ```

 2. Now you can enable the Auditor app in the configuration:
    ```nix
    {
      keyStorePath = "/dev/shm/android-keys";
      signing.enable = true;

      apps = {
        auditor.enable = true;
        auditor.domain = "attestation.example.com";
      };
    }
    ```
    You also need to have signing enabled during build time because the Auditor
    app needs to know its own signing key during build.

 3. That's it from the Android side.  Note that the custom Auditor app will be
    named “Robotnix Auditor”.  When you build GrapheneOS the normal Auditor app
    will still be there, don't get confused (like I did).

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

 2. Now you can import Robotnix in your NixOS configuration with the
    aforementioned fingerprints.
    ```nix
    { config, lib, pkgs, ... }:
    {
      imports = [
        ((builtins.fetchTarball {
          name = "robotnix";
          url =
            "https://github.com/danielfullmer/robotnix/archive/61b91d145f0b08cf0d4d73fb1d7ba74b9899b788.zip";
          sha256 = "1dihmdw5w891jq2fm7mcx30ydjjd33ggbb60898841x5pzjx6ynv";
        }) + "/nixos")
      ];

      services.attestation-server = {
        enable = true;
        domain = "attestation.example.com";
        deviceFamily = "sunfish";
        signatureFingerprint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        avbFingerprint = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
      };
      services.nginx.virtualHosts."${config.services.attestation-server.domain}" = {
        enableACME = true;
        #locations."/api/create_account".return = "404"; # uncomment to disable account creation
      };
    }
    ```

 3. Register and optionally disable account creation.  The start the “Robotnix
    Auditor” app on your phone and open the menu (three dots).  Choose “Enable
    remote verification” and scan the QR code on your attestation server.

 4. The attestation server keeps its state in `/var/lib/private/attestation`.
    **Make periodic backups!**
