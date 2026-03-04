{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.signing;
  yubikeyGenerateScript =
    {
      exportOnly,
    }:
    pkgs.writeShellScript "yubikey-${if exportOnly then "extract-certificates" else "generate-keys"}.sh" ''
      set -euo pipefail
      export PATH=${
        lib.makeBinPath (
          with pkgs;
          [
            coreutils
            yubikey-manager
            gawk
            openssl
            android-tools
          ]
        )
      }

      if [[ "$#" -ne 2 ]]; then
        echo "Usage: $0 <keysdir> <pin-file>"
        exit 1
      fi

      KEYSDIR="$1"
      PIN_FILE="$2"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          key: slot:
          let
            algo =
              if key == cfg.avb.key then "RSA${toString cfg.avb.size}" else "RSA${toString cfg.apkKeySize}";
          in
          ''
            ${lib.optionalString (!exportOnly) ''
              # Check if this slot is already occupied
              # I wonder if there's a less dogshit hacky way to do this.
              FAILED=0
              OUTPUT=$(ykman piv keys info ${slot} 2>&1) || FAILED=1
              if [ $FAILED -ne 1 ]; then
                echo "YubiKey PIV key slot ${slot} already contains a key."
                echo "Either change the slot mapping via signing.pkcs11.presets.yubikey-piv.slotMap,"
                echo "or erase the key slot manually."
                exit 1
              fi

              if [[ ! "$OUTPUT" =~ "^ERROR: No key stored in slot" ]]; then
                echo "failed to run \"ykman piv keys info ${slot}\":"
                echo "stderr: $OUTPUT"
                exit 1
              fi

              echo "Generating ${key} in PIV slot ${slot}"
              echo | ykman piv keys generate -a ${algo} ${slot} /dev/null
              echo "Generating certificate for ${key} in PIV slot ${slot}"
              mkdir -p $(dirname "$KEYSDIR/${key}.x509.pem")
              cat <(echo) $PIN_FILE | ykman piv certificates generate ${slot} -s "${cfg.keyCN} ${
                builtins.replaceStrings [ "/" ] [ "-" ] key
              }"
            ''}
            echo "Extracting certificate for ${key} from PIV slot ${slot}"
            ykman piv certificates export ${slot} "$KEYSDIR/${key}.x509.pem"
          ''
        ) cfg.pkcs11.presets.yubikey-piv.slotMap
      )}

      # Generate AVB public key metadata blob. We can't just pipe from
      # openssl to avbtool, because avbtool executes openssl on the key
      # file internally without passing stdin...
      TMPFILE=$(mktemp)
      openssl x509 -in "$KEYSDIR/${cfg.avb.key}.x509.pem" -noout -pubkey > "$TMPFILE"
      avbtool extract_public_key --key "$TMPFILE" --output "$KEYSDIR/${cfg.avb.key}_pkmd.bin"
      rm "$TMPFILE"
    '';
in
lib.mkIf cfg.pkcs11.presets.yubikey-piv.enable {
  build = {
    yubikeyGenerateKeysScript = yubikeyGenerateScript {
      exportOnly = false;
    };

    yubikeyExportCertificatesScript = yubikeyGenerateScript {
      exportOnly = true;
    };

    yubikeyImportKeysScript = pkgs.writeShellScript "yubikey-import-keys.sh" ''
      set -euo pipefail
      export PATH=${
        lib.makeBinPath (
          with pkgs;
          [
            coreutils
            yubikey-manager
          ]
        )
      }

      if [[ "$#" -ne 1 ]]; then
        echo "Usage: $0 <keysdir>"
        exit 1
      fi

      KEYSDIR="$1"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          key: slot:
          let
            isAvbKey = key == cfg.avb.key;
            suffix = if isAvbKey then ".pem" else ".pk8";
          in
          ''
            echo "Importing ${key}..."
            echo | ykman piv keys import ${slot} "$KEYSDIR/${key}${suffix}"
            ${lib.optionalString isAvbKey ''
              if [ ! -f "$KEYSDIR/${key}.x509.pem" ]; then
                echo "AVB certificate $KEYSDIR/${key}.x509.pem does not exist."
                echo "Perhaps you have generated your keys before PKCS#11 signing was introduced."
                echo "You can re-generate the AVB certificate by re-running generateKeysScript."
                exit 1
              fi
            ''}
            echo | ykman piv certificates import ${slot} "$KEYSDIR/${key}.x509.pem"
            echo
          ''
        ) cfg.pkcs11.presets.yubikey-piv.slotMap
      )}
    '';
  };
}
