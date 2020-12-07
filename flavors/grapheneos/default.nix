{ config, pkgs, lib, ... }:
with lib;
let
  grapheneOSRelease = "${config.apv.buildID}.2020.11.27.15";

  phoneDeviceFamilies = [ "crosshatch" "bonito" "coral" "sunfish" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

in mkIf (config.flavor == "grapheneos") (mkMerge [
{
  # This a default datetime for robotnix that I update manually whenever
  # significant a change is made to anything the build depends on. It does not
  # match the datetime used in the GrapheneOS build above.
  buildDateTime = mkDefault 1607246070;

  source.dirs = lib.importJSON (./. + "/repo-${grapheneOSRelease}.json");

  apv.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
  apv.buildID = mkDefault "RP1A.201105.002";

  # Not strictly necessary for me to set these, since I override the source.dirs above
  source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  warnings = (optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for GrapheneOS")
    ++ (optional (config.androidVersion != 11) "Unsupported androidVersion (!= 11) for GrapheneOS");
}
{
  # TODO: Temporarily revert the SELinux improvements in GrapheneOS
  # 2020.10.23.04, which breaks webview/Vanadium in Robotnix caused by (for
  # example) the "remove base system app execmem" commit and others.
  # webview/Vanadium ought to be signed by non-system keys.
  source.dirs."system/sepolicy".src = pkgs.fetchgit {
    url = "https://github.com/GrapheneOS/platform_system_sepolicy";
    rev = "RP1A.201005.004.2020.10.06.02";
    sha256 = "0wrmc9abkgrk92j18g0qvkfsw84kl3rmx5c86kycb9sbbg2hjmgn";
  };
  source.dirs."device/google/bonito-sepolicy".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/device_google_bonito-sepolicy/commit/2304fe5f0496a28158ef543dcecb3eab6d5bf3e1.patch";
      sha256 = "0xirwffij0inwnj1svvg5na2ri8zkw5njdb5g6cc5h2gp11spfcs";
      revert = true;
    })
  ];
  source.dirs."device/google/crosshatch-sepolicy".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/device_google_crosshatch-sepolicy/commit/e67d01dac4917f8413118b6ba1d9ddc45e998c40.patch";
      sha256 = "0xirwffij0inwnj1svvg5na2ri8zkw5njdb5g6cc5h2gp11spfcs";
      revert = true;
    })
  ];
  source.dirs."device/google/coral-sepolicy".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/device_google_coral-sepolicy/commit/bde429f13a9737b3e5ff074d4a27dc879c0c3e29.patch";
      sha256 = "0ccmq79q0jyzqgw74wmg9w09mlymqm5g2sil6qi7y24f0wahlx8l";
      revert = true;
    })
  ];
  source.dirs."device/google/sunfish-sepolicy".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/device_google_sunfish-sepolicy/commit/0510011d062f96683ee923282a91ae882d5dcb95.patch";
      sha256 = "1mwgiqbdk99vl7zrqb8n8hs7w8sxvdkrf5pz9n9i47kkdp86p6g3";
      revert = true;
    })
  ];

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
  source.dirs."kernel/google/coral".enable = false;
  source.dirs."kernel/google/sunfish".enable = false;

  # Enable Vanadium (GraphaneOS's chromium fork).
  apps.vanadium.enable = mkDefault true;
  webview.vanadium.enable = mkDefault true;
  webview.vanadium.availableByDefault = mkDefault true;

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
(mkIf (elem config.deviceFamily [ "taimen" "muskie" "crosshatch" "bonito" "coral" "sunfish" ]) {
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
    sha256 = "1hp6k886n34kj73wws234d209ykf1j3mg2mgzk9dckriw63m73my";
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
    sha256 = "0gsbbd8mq9sfj4s0km15vkzls26nff2g0ssi8jccb7zclfbqazqj";
    fetchSubmodules = true;
  };
})
(mkIf (config.deviceFamily == "sunfish") {
  kernel.src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "kernel_google_sunfish";
    rev = grapheneOSRelease;
    sha256 = "1cxm3k9wvfbdv5w583mq2bp306j62k4g1cwlnbrgm53yfyqrimsd";
    fetchSubmodules = true;
  };
})
])
