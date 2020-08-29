{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.signing;
in
{
  options = {
    signing = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Whether to sign build using user-provided keys. Otherwise, build will be signed using insecure test-keys.";
      };

      signTargetFilesArgs = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
      };

      avb = {
        enable = mkEnableOption "AVB signing";

        # TODO: Refactor
        mode = mkOption {
          type = types.strMatching "(verity_only|vbmeta_simple|vbmeta_chained|vbmeta_chained_v2)";
          default  = "vbmeta_chained";
        };
      };

      apex = {
        enable = mkEnableOption "APEX signing";

        packageNames = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "APEX packages which need to be signed";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    signing.signTargetFilesArgs = let
      avbFlags = {
        verity_only = [
          "--replace_verity_public_key $KEYSDIR/verity_key.pub"
          "--replace_verity_private_key $KEYSDIR/verity"
          "--replace_verity_keyid $KEYSDIR/verity.x509.pem"
        ];
        vbmeta_simple = [
          "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained = [
          "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained_v2 = [
          "--avb_vbmeta_key $KEYSDIR/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
          "--avb_vbmeta_system_key $KEYSDIR/avb.pem" "--avb_vbmeta_system_algorithm SHA256_RSA2048"
        ];
      }.${cfg.avb.mode}
      ++ optionals ((config.androidVersion >= 10) && (cfg.avb.mode != "verity_only")) [
        "--avb_system_other_key $KEYSDIR/avb.pem"
        "--avb_system_other_algorithm SHA256_RSA2048"
      ];
    in
      optional (config.androidVersion >= 10) "--key_mapping build/target/product/security/networkstack=$KEYSDIR/networkstack"
      ++ optionals cfg.avb.enable avbFlags
      ++ optionals cfg.apex.enable (map (k: "--extra_apks ${k}.apex=$KEYSDIR/${k} --extra_apex_payload_key ${k}.apex=$KEYSDIR/${k}.pem") cfg.apex.packageNames);
  };
}
