{ config, pkgs, lib, ... }:
with lib;
let
  release = rec {
    marlin = {
      tag = "PQ3A.190801.002.2019.08.05.19";
      sha256 = "0bkhs3ncfx7s334hg1f3gambsvifv6nah440s84rslb0gvhj89kf";
    };
    taimen = marlin;
    crosshatch = marlin;
    bonito = {
      tag = "PQ3B.190801.002.2019.08.05.19";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    };
  }.${config.deviceFamily};
  crosshatchKernel = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_crosshatch";
    rev = release.tag;
    sha256 = "1r3pj5fv2a2zy1kjm9cc49j5vmscvwpvlx5hffhc9r8jbc85acgi";
    fetchSubmodules = true;
  };
in
{
  manifest = {
    url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    rev = mkDefault "refs/tags/${release.tag}";
    sha256 = mkDefault release.sha256;
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
