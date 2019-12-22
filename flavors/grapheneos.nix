{ config, pkgs, lib, ... }:
with lib;
let
  kernelName = if (config.deviceFamily == "taimen") then "wahoo" else config.deviceFamily;
  configNameMap = {
    sailfish = "marlin";
    sargo = "bonito";
  };
  grapheneOSRelease = "2019.12.02.23";
in mkMerge [
(mkIf ((config.flavor == "grapheneos") && (elem config.deviceFamily [ "taimen" "crosshatch" ])) {
  source.buildNumber = "QQ1A.191205.008";
  source.manifest.sha256 = "1a3q8cs3n9r02p5rn03y9dgk18q9i21cf5678h8w6qgqb2b7l1b5";
})
(mkIf ((config.flavor == "grapheneos") && (config.deviceFamily == "bonito")) {
  source.buildNumber = "QQ1A.191205.011";
  source.manifest.sha256 = "0b8s7qch9a2b9kafrxs3xmcai7d5a0sk5p0kr3ws3idc53szny5q";
})
(mkIf ((config.flavor == "grapheneos") && (elem config.deviceFamily [ "crosshatch" "bonito" ])) {
  # Hack for crosshatch/bonito since they uses submodules and repo2nix doesn't support that yet.
  kernel.src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_crosshatch";
    # TODO: Override for just this grapheneos release, since this refers to an old commit for techpack/audio submodule
    rev = "57bb6aab22f3c8e6059ed6f9088052a458599da8";
    sha256 = "0bhzdpd7fmfzh1dvxpfsz4993wqyrbzy62vkl7w328b3r5b0i0f6";
    fetchSubmodules = true;
  };
})
(mkIf (config.flavor == "grapheneos") {
  source.manifest.url = "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = "refs/tags/${config.source.buildNumber}.${grapheneOSRelease}";

  # Hack for crosshatch/bonito since they use submodules and repo2nix doesn't support that yet.
  kernel.useCustom = mkDefault true;
  kernel.src = mkDefault config.source.dirs."kernel/google/${kernelName}".contents;
  kernel.configName = mkForce (if (hasAttr config.device configNameMap) then configNameMap.${config.device} else config.device);

  # No need to include these in AOSP build source since we build separately
  source.dirs."kernel/google/marlin".enable = false;
  source.dirs."kernel/google/wahoo".enable = false;
  source.dirs."kernel/google/crosshatch".enable = false;
  source.dirs."kernel/google/bonito".enable = false;

  # Enable Vanadium (GraphaneOS's chromium fork). It currently doesn't work with Android 10?
  #apps.vanadium.enable = true; # Just stick to using their prebuilt vanadium for now
  #webview.vanadium.enable = true;
  #webview.vanadium.availableByDefault = true;
  removedProductPackages = [ "webview" "Vanadium" ]; # Remove from  build. We'll re-add it ourselves
  webview.prebuilt = {
    apk = config.source.dirs."external/chromium-webview".contents + "/prebuilt/arm64/webview.apk";
    availableByDefault = mkDefault true;
    enable = mkDefault true;
  };

  # GrapheneOS just disables apex updating wholesale
  apex.enable = false;

  # Don't include updater by default since it would download updates signed with grapheneos's keys.
  # TODO: Encourage user to set apps.updater.enable
  source.dirs."packages/apps/Updater".enable = false;

  # Leave the existing auditor in the build--just in case the user wants to
  # audit devices using the official upstream build

  source.dirs."vendor/android-prepare-vendor".enable = false; # Use our own pinned version
})
]
