{ config, lib, ... }:
with lib;
let
  tag = {
    marlin = "PQ3A.190705.001.2019.07.01.21";
    taimen = "PQ3A.190705.001.2019.07.01.21";
    crosshatch = "PQ3A.190705.003.2019.07.01.21";
    bonito = "PQ3B.190705.003.2019.07.01.21";
  }.${config.deviceFamily};
  releases = {
    # TODO: Add all releases
    "PQ3A.190705.001.2019.07.01.21" = {
      rev = "094a8e7d070094a6b927a615de3254ce0640ddb5";
      sha256 = "0k24946sxad8pn560sjianpf0d5mpn38dv0yw3pm6x3hj64j8g58";
    };
  };
in
{
  manifest = {
    url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    rev = mkDefault releases.${tag}.rev;
    sha256 = mkDefault releases.${tag}.sha256;
  };

  kernel.src = mkDefault (config.build.sourceDir "kernel/google/${config.deviceFamily}");

  apps.webview.enable = mkDefault true;
  # TODO: Build and include vanadium

  apps.updater.enable = mkDefault true;
  apps.updater.src = mkDefault null; # Already included in platform manifest
}
