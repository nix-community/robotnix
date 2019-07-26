with (import <nixpkgs> {});
{
  imports = [ ./example.nix ];
  device = "crosshatch";
  avb.pkmd = ./keys/crosshatch/avb_pkmd.bin;
  certs.platform.x509 = ./keys/crosshatch/platform.x509.pem;  # Used by fdroid privileged extension to whitelist org.fdroid.fdroid
}
