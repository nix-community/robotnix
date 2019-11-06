{ config, pkgs, lib, ... }:
with lib;
let
  release = rec {
    taimen = {
      tag = "QP1A.191105.004.2019.11.05.23";
      sha256 = "0r02alkgb0kdvh1c7y8295agl1n69msggkvaifvbrhk071zrfqqw";
    };
    crosshatch = {
      tag = "QP1A.191105.003.2019.11.05.23";
      sha256 = "1a2572ivzcdnnjc8bps3y1ra2jm7r3vwxz9mvijncwnzi3dx6wcm";
      kernelSha256 = "0nyc9ndlrbpw0zc4fyap9rkf285xbvwxw42k1q4a63cghz5nl6j2";
    };
    bonito = crosshatch;
    x86_64 = taimen; # Emulator target
  }.${config.deviceFamily};

  # Hack for crosshatch since it uses submodules and repo2nix doesn't support that yet.
  kernelSrc = device: pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_${device}";
    rev = release.tag;
    sha256 = release.kernelSha256;
    fetchSubmodules = true;
  };

  kernelName = if (config.deviceFamily == "taimen") then "wahoo" else config.deviceFamily;

  configNameMap = {
    sailfish = "marlin";
    sargo = "bonito";
  };
  configName = if (hasAttr config.device configNameMap) then configNameMap.${config.device} else config.device;
in
mkIf (config.flavor == "grapheneos") {
  source.manifest = {
    url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    rev = mkDefault "refs/tags/${release.tag}";
    sha256 = mkDefault release.sha256;
  };

  # Hack for crosshatch since it uses submodules and repo2nix doesn't support that yet.
  kernel.useCustom = mkDefault true;
  kernel.src = mkDefault (if (elem config.deviceFamily ["crosshatch" "bonito"])
    then kernelSrc (if (config.androidVersion >= 10) then "crosshatch" else kernelName)
    else config.source.dirs."kernel/google/${kernelName}".contents);
  kernel.configName = mkForce configName;

  # No need to include these in AOSP build since we build separately
  source.dirs."kernel/google/marlin".enable = false;
  source.dirs."kernel/google/wahoo".enable = false;
  source.dirs."kernel/google/crosshatch".enable = false;
  source.dirs."kernel/google/bonito".enable = false;

  # GrapheneOS just disables apex updating wholesale
  apex.enable = false;

  # TODO: Build and include vanadium
  removedProductPackages = mkIf (config.androidVersion == 9) [ "Vanadium" ];

  # Don't include updater by default since it would download updates signed with grapheneos's keys.
  # TODO: Encourage user to set apps.updater.enable
  source.dirs."packages/apps/Updater".enable = false;

  # Leave the existing auditor in the build--just in case the user wants to
  # audit devices using the official upstream build

  source.dirs."vendor/android-prepare-vendor".enable = false; # Use our own pinned version
}
