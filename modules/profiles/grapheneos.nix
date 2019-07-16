{ config, lib, ... }:
with lib;
let
  tag = {
    marlin = "PQ3A.190705.001.2019.07.16.22";
    taimen = "PQ3A.190705.001.2019.07.16.22";
    crosshatch = "PQ3A.190705.003.2019.07.16.22";
    bonito = "PQ3B.190705.003.2019.07.16.22";
  }.${config.deviceFamily};
  releases = {
    # TODO: Add all releases
    "PQ3A.190705.001.2019.07.16.22" = {
      rev = "1bd882ec78e3740ef981004919cbfe6386e218c3";
      sha256 = "1jy47x1qg87yv190jssqpdmx4w1632g0jnnhiszcmdqkkhwr9pwd";
    };
  };
in
{
  source.manifest = {
    url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    rev = mkDefault releases.${tag}.rev;
    sha256 = mkDefault releases.${tag}.sha256;
  };

  kernel.src = mkDefault (config.source.dirs."kernel/google/${config.deviceFamily}");

#  apps.webview.enable = mkDefault true;
  # TODO: Build and include vanadium
  removedProductPackages = [ "Vanadium" ];

#  apps.updater.enable = mkDefault true;
#  apps.updater.src = mkDefault null; # Already included in platform manifest
}
