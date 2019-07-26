
with (import <nixpkgs> {});
{
  imports = [ ./example.nix ];
  device = "marlin";
  certs.verity.x509 = ./keys/marlin/verity.x509.pem;  # Only necessary for marlin (Pixel XL) since the kernel build needs to include this cert
  certs.platform.x509 = ./keys/marlin/platform.x509.pem;  # Used by fdroid privileged extension to whitelist org.fdroid.fdroid
}
