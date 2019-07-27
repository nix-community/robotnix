with (import <nixpkgs> {});
{
  imports = [ ./example.nix ];
  device = "crosshatch";
  avb.pkmd = /var/secrets/android-keys/crosshatch/avb_pkmd.bin;
  certs.platform.x509 = /var/secrets/android-keys/crosshatch/platform.x509.pem;  # Used by fdroid privileged extension to whitelist org.fdroid.fdroid
}
