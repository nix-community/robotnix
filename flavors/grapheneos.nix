{ config, pkgs, lib, ... }:
with lib;
let
  kernelName = if (config.deviceFamily == "taimen") then "wahoo" else config.deviceFamily;
  configNameMap = {
    sailfish = "marlin";
    sargo = "bonito";
  };
  grapheneOSRelease = "2020.01.06.21";
in mkIf (config.flavor == "grapheneos") (mkMerge [
(mkIf (elem config.deviceFamily [ "taimen" "crosshatch" "bonito" ]) {
  source.buildNumber = "QQ1A.200105.002";
  source.manifest.sha256 = "14r4g0zbp6c10li266vg71c5b1vvdkhi5fgv03wc290v1jzw5978";
})
(mkIf (elem config.deviceFamily [ "crosshatch" "bonito" ]) {
  # Hack for crosshatch/bonito since they uses submodules and repo2nix doesn't support that yet.
  kernel.src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_crosshatch";
    rev = "${config.source.buildNumber}.${grapheneOSRelease}";
    sha256 = "02lrkvgkaqjvzjbn9yl0ylf3b38bld57pm7bnvcj79ng9gx20qzc";
    fetchSubmodules = true;
  };
})
{
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
    apk = config.source.dirs."external/chromium-webview".contents + "/prebuilt/${config.arch}/webview.apk";
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
}
])
