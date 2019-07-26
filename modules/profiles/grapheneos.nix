{ config, pkgs, lib, ... }:
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
    "PQ3A.190705.003.2019.07.16.22" = {
      rev = "4e50473ea1f222f04ba127017014e6405e8f074f";
      sha256 = "0xzr88qq19d5mpvp9faw3f7a76rj0wi3vbpjp0n18qlvl53qzr6k";
    };
  };
  crosshatchKernel = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_crosshatch";
    rev = "230e12d1f6c915f0f5604ab0de0d10ff036eb531";
    sha256 = "07mhlm7yy82z60y9jf499ygbd3w89jpcc27s9k4c695c43yi6mkc";
    fetchSubmodules = true;
  };
in
{
  manifest = {
    url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    rev = mkDefault releases.${tag}.rev;
    sha256 = mkDefault releases.${tag}.sha256;
  };

  # Hack for crosshatch since it uses submodules and repo2nix doesn't support that yet.
  kernel.src = mkDefault (if config.deviceFamily == "crosshatch" then crosshatchKernel else config.build.sourceDir "kernel/google/${config.deviceFamily}");
  kernel.configName = mkIf (config.deviceFamily == "crosshatch") config.device; # GrapheneOS uses different config names than upstream

  # See https://stackoverflow.com/questions/55078766/mdss-pll-trace-h-file-not-found-error-compiling-kernel-4-9-for-android?noredirect=1 and https://lwn.net/Articles/383362/
  kernel.patches = mkIf (config.deviceFamily == "crosshatch") [ ./crosshatch-kernel.patch ];

  apps.webview.enable = mkDefault true;
  # TODO: Build and include vanadium
  removedProductPackages = [ "Vanadium" ];

  apps.updater.enable = mkDefault true;
  apps.updater.src = mkDefault null; # Already included in platform manifest
}
