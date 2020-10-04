{ config, pkgs, lib, ... }:
with lib;
let
  grapheneOSRelease =
    if config.androidVersion == 11 then "${config.apv.buildID}.2020.09.29.20"
    else if config.androidVersion == 10 then "${config.apv.buildID}.2020.09.11.14"
    else throw "Invalid androidVersion for GrapheneOS";

  phoneDeviceFamilies = [ "taimen" "muskie" "crosshatch" "bonito" "coral" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

in mkIf (config.flavor == "grapheneos") (mkMerge [
{
  #androidVersion = mkDefault 11;

  # This a default datetime for robotnix that I update manually whenever
  # significant a change is made to anything the build depends on. It does not
  # match the datetime used in the GrapheneOS build above.
  buildDateTime = mkMerge [
    (mkIf (config.androidVersion == 11) (mkDefault 1601774578))
    (mkIf (config.androidVersion == 10) (mkDefault 1599972803))
  ];

  source.dirs = lib.importJSON (./. + "/repo-${grapheneOSRelease}.json");

  apv.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
  apv.buildID = mkMerge [
    (mkIf (config.androidVersion == 11) (mkDefault "RP1A.200720.009"))
    (mkIf (config.androidVersion == 10) (mkDefault "QQ3A.200805.001"))
  ];

  # Not strictly necessary for me to set these, since I override the jsonFile
  source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  warnings = (optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for GrapheneOS")
    ++ (optional (config.androidVersion < 11) "Old unsupported android version selected for GrapheneOS.");
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

  # Temporarily use a recent upstream prebuilt webview until we use a chromium version that supports API >= 30
  webview.prebuilt.enable = mkIf (config.androidVersion == 11) (mkDefault true);
  webview.prebuilt.apk = config.source.dirs."external/chromium-webview".src + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;
  webview.prebuilt.packageName = "com.google.android.webview";

  apps.seedvault.enable = mkDefault true;

  # Remove upstream prebuilt versions from build. We build from source ourselves.
  removedProductPackages = [ "TrichromeWebView" "TrichromeChrome" "webview" "Seedvault" ];
  source.dirs."external/vanadium".enable = false;
  source.dirs."external/seedvault".enable = false;
  source.dirs."vendor/android-prepare-vendor".enable = false; # Use our own pinned version

  # GrapheneOS just disables apex updating wholesale
  signing.apex.enable = false;

  # Don't include updater by default since it would download updates signed with grapheneos's keys.
  # TODO: Encourage user to set apps.updater.enable
  source.dirs."packages/apps/Updater".enable = false;

  # Leave the existing auditor in the build--just in case the user wants to
  # audit devices using the official upstream build
}
(mkIf (elem config.deviceFamily [ "taimen" "muskie" "crosshatch" "bonito" "coral" ]) {
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
    sha256 = {
      "10" = "0l86yrj40jcm144sc7hmqc6mz5k67fh3gn2yf8hd6dp28ynrwrhd";
      "11" = "1zbqqjwdnibahcghsw3qrgdk30dsnbnxq1z66c9g1mni48rhxy11";
    }."${builtins.toString config.androidVersion}";
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
(mkIf (config.deviceFamily == "coral") {
  kernel.configName = mkForce "floral";
  kernel.src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_coral";
    rev = grapheneOSRelease;
    sha256 = {
      "10" = "0jjzp37q01xz32ygji8drxfa55g5lb2qh9n2l39313w94g999ci9";
      "11" = "0jdq96jfk61qn6wyxx71brfpm3alsbj93ywfqrid8jcsim1i5xgj";
    }."${builtins.toString config.androidVersion}";
    fetchSubmodules = true;
  };
})
])
