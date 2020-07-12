{ config, pkgs, lib, ... }:
with lib;
let
  grapheneOSRelease = "${config.apv.buildID}.2020.07.06.20";

  phoneDeviceFamilies = [ "taimen" "muskie" "crosshatch" "bonito" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

in mkIf (config.flavor == "grapheneos") (mkMerge [
{
  # This a default number for robotnix that I update manually whenever
  # significant a change is made to anything the build depends on. It does not
  # match the GrapheneOS build number above.
  buildNumber = mkDefault "2020.07.07.10";
  buildDateTime = mkDefault 1594141956;

  source.dirs = lib.importJSON (./. + "/repo-${grapheneOSRelease}.json");

  apv.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
  apv.buildID = mkDefault "QQ3A.200705.002";

  # Not strictly necessary for me to set these, since I override the jsonFile
  source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  warnings = optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for GrapheneOS";
}
{
  # Disable setting SCHED_BATCH in soong. Brings in a new dependency and the nix-daemon could do that anyway.
  source.dirs."build/soong".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_build_soong/commit/76723b5745f08e88efa99295fbb53ed60e80af92.patch";
      sha256 = "0vvairss3h3f9ybfgxihp5i8yk0rsnyhpvkm473g6dc49lv90ggq";
      revert = true;
    })
  ];

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
(mkIf (elem config.deviceFamily [ "taimen" "muskie" "crosshatch" "bonito" ]) {
  kernel.useCustom = mkDefault true;
  kernel.src = mkDefault config.source.dirs."kernel/google/${config.kernel.name}".src;
  kernel.configName = config.device;
  kernel.relpath = "device/google/${config.device}-kernel";
})
(mkIf (elem config.deviceFamily [ "crosshatch" "bonito" ]) {
  # Hack for crosshatch/bonito since they use submodules and repo2nix doesn't support that yet.
  kernel.src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_crosshatch";
    rev = grapheneOSRelease;
    sha256 = "01zpcjhhbqgpli7zn1fv698193fkdcj2p4f6ix19hig35j3brcyc";
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
