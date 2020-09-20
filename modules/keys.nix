{ config, pkgs, lib, ... }:

with lib;
let
  # Get a bunch of utilities to generate keys
  keyTools = pkgs.runCommandCC "android-key-tools" { buildInputs = [ pkgs.python ]; } ''
    mkdir -p $out/bin

    cp ${config.source.dirs."development".src}/tools/make_key $out/bin/make_key
    substituteInPlace $out/bin/make_key --replace openssl ${getBin pkgs.openssl}/bin/openssl

    cc -o $out/bin/generate_verity_key \
      ${config.source.dirs."system/extras".src}/verity/generate_verity_key.c \
      ${config.source.dirs."system/core".src}/libcrypto_utils/android_pubkey.c \
      -I ${config.source.dirs."system/core".src}/libcrypto_utils/include/ \
      -I ${pkgs.boringssl}/include ${pkgs.boringssl}/lib/libssl.a ${pkgs.boringssl}/lib/libcrypto.a -lpthread

    cp ${config.source.dirs."external/avb".src}/avbtool $out/bin/avbtool

    patchShebangs $out/bin
  '';
in {
  options = {
    generateKeysScript = mkOption { type = types.path; internal = true; };
  };

  config = {
    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    generateKeysScript = let
      keysToGenerate = [ "releasekey" "platform" "shared" "media" ]
                        ++ (optional (config.signing.avb.mode == "verity_only") "verity")
                        ++ (optionals (config.androidVersion >= 10) [ "networkstack" ] ++ config.signing.apex.packageNames);
    in mkDefault (pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      for key in ${toString keysToGenerate}; do
        # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
        ! make_key "$key" "$1"
      done

      ${optionalString (config.signing.avb.mode == "verity_only") "generate_verity_key -convert verity.x509.pem verity_key"}

      # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
      ${optionalString (config.signing.avb.mode != "verity_only") ''
        openssl genrsa -out avb.pem 2048
        avbtool extract_public_key --key avb.pem --output avb_pkmd.bin
      ''}

      ${concatMapStringsSep "\n" (k: ''
        openssl genrsa -out ${k}.pem 4096
        avbtool extract_public_key --key ${k}.pem --output ${k}.avbpubkey
      '') config.signing.apex.packageNames}
    '');
  };
}
