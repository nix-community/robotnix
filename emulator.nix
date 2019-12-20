{ lib, ... }:

with lib;
{
  imports = [ ./example.nix ];
  device = "x86_64";
  variant = "userdebug";
  kernel.useCustom = false;
  apps.auditor.enable = mkForce false;
  vendor.img = null;
  androidVersion = 10;
}
