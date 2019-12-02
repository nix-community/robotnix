{ config, pkgs, lib, ... }:
with lib;
let
  release = rec {
    taimen = {
      tag = "QQ1A.191205.008.2019.12.02.23";
      sha256 = "1a3q8cs3n9r02p5rn03y9dgk18q9i21cf5678h8w6qgqb2b7l1b5";
    };
    crosshatch = taimen // {
      kernelSha256 = "0bhzdpd7fmfzh1dvxpfsz4993wqyrbzy62vkl7w328b3r5b0i0f6";
    };
    bonito = {
      tag = "QQ1A.191205.011.2019.12.02.23";
      sha256 = "0b8s7qch9a2b9kafrxs3xmcai7d5a0sk5p0kr3ws3idc53szny5q";
      kernelSha256 = "0bhzdpd7fmfzh1dvxpfsz4993wqyrbzy62vkl7w328b3r5b0i0f6";
    };
    x86_64 = bonito; # Emulator target
  }.${config.deviceFamily};

  # Hack for crosshatch since it uses submodules and repo2nix doesn't support that yet.
  kernelSrc = device: pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_${device}";
    # TODO: Override for just this grapheneos release, since this refers to an old commit for techpack/audio submodule
    rev = if (device == "crosshatch") then "57bb6aab22f3c8e6059ed6f9088052a458599da8" else release.tag;
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

  # Hack for crosshatch/bonito since they use submodules and repo2nix doesn't support that yet.
  kernel.useCustom = mkDefault true;
  kernel.src = mkDefault (if (elem config.deviceFamily ["crosshatch" "bonito"]) # Pixel 3 and 3a use the same kernel source
    then kernelSrc "crosshatch"
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
