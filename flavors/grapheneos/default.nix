{ config, pkgs, lib, ... }:
with lib;
let
  grapheneOSRelease = "${config.vendor.buildID}.2020.04.07.10";
in mkIf (config.flavor == "grapheneos") (mkMerge [
{
  buildNumber = mkDefault "2020.04.07.13";
  buildDateTime = mkDefault 1586279715;
  vendor.buildID = mkDefault "QQ2A.200405.005";

  source.jsonFile = ./. + "/${grapheneOSRelease}.json";

  # Not strictly necessary for me to set these, since I override the jsonFile
  source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  kernel.useCustom = mkDefault true;
  kernel.src = mkDefault config.source.dirs."kernel/google/${config.kernel.name}".contents;
  kernel.configName = config.device;
  kernel.relpath = "device/google/${config.device}-kernel";

  # No need to include these in AOSP build source since we build separately
  source.dirs."kernel/google/marlin".enable = false;
  source.dirs."kernel/google/wahoo".enable = false;
  source.dirs."kernel/google/crosshatch".enable = false;
  source.dirs."kernel/google/bonito".enable = false;

  # Enable Vanadium (GraphaneOS's chromium fork).
  apps.vanadium.enable = mkDefault true;
  webview.vanadium.enable = mkDefault true;
  webview.vanadium.availableByDefault = mkDefault true;

  apps.seedvault.enable = mkDefault true;

# Remove upstream prebuilt versions from build. We build from source ourselves.
  removedProductPackages = [ "TrichromeWebView" "TrichromeChrome" "Seedvault" ];
  source.dirs."external/vanadium".enable = false;
  source.dirs."external/seedvault".enable = false;
  source.dirs."vendor/android-prepare-vendor".enable = false; # Use our own pinned version

  # GrapheneOS just disables apex updating wholesale
  apex.enable = false;

  # Don't include updater by default since it would download updates signed with grapheneos's keys.
  # TODO: Encourage user to set apps.updater.enable
  source.dirs."packages/apps/Updater".enable = false;

  # Leave the existing auditor in the build--just in case the user wants to
  # audit devices using the official upstream build
}
(mkIf (elem config.deviceFamily [ "crosshatch" "bonito" ]) {
  # Hack for crosshatch/bonito since they use submodules and repo2nix doesn't support that yet.
  kernel.src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_crosshatch";
    rev = grapheneOSRelease;
    sha256 = "16di46kmlzm6hrkxd95ddaa07yhxvzkv7ah8d6zki6scpwj1pjkm";
    fetchSubmodules = true;
  };
})
(mkIf (config.device == "sargo") { # TODO: Ugly hack
  kernel.configName = mkForce "bonito";
  kernel.relpath = mkForce "device/google/bonito-kernel";
})
(mkIf (config.device == "blueline") { # TODO: Ugly hack
  kernel.relpath = mkForce "device/google/blueline-kernel";
})
])
