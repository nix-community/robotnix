{ config, pkgs, lib, ... }:

with lib;
let
  # Get a bunch of utilities to generate keys
  keyTools = pkgs.runCommandCC "android-key-tools" { buildInputs = [ pkgs.python ]; } ''
    mkdir -p $out/bin

    cp ${config.source.dirs."development".src}/tools/make_key $out/bin/make_key
    substituteInPlace $out/bin/make_key --replace openssl ${getBin pkgs.openssl}/bin/openssl

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
                        ++ (optional (config.avbMode == "verity_only") "verity")
                        ++ (optionals (config.androidVersion >= 10) [ "networkstack" ] ++ config.apex.packageNames);
      avbKeysToGenerate = config.apex.packageNames;
    in mkDefault (pkgs.writeScript "generate_keys.sh" ''
      #!${pkgs.runtimeShell}

      export PATH=${getBin pkgs.openssl}/bin:${keyTools}/bin:$PATH

      for key in ${toString keysToGenerate}; do
        # make_key exits with unsuccessful code 1 instead of 0, need ! to negate
        ! make_key "$key" "$1" || exit 1
      done

      ${optionalString (config.avbMode == "verity_only") "generate_verity_key -convert verity.x509.pem verity_key || exit 1"}

      # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
      ${optionalString (config.avbMode != "verity_only") ''
        openssl genrsa -out avb.pem 2048 || exit 1
        avbtool extract_public_key --key avb.pem --output avb_pkmd.bin || exit 1
      ''}

      ${concatMapStringsSep "\n" (k: ''
        openssl genrsa -out ${k}.pem 4096 || exit 1
        avbtool extract_public_key --key ${k}.pem --output ${k}.avbpubkey || exit 1
      '') avbKeysToGenerate}
    '');
  };
}
