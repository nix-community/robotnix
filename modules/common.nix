{ config, pkgs, lib, ... }:

with lib;
let
  flex = pkgs.callPackage ../misc/flex-2.5.39.nix {};
in
mkMerge [
(mkIf (config.androidVersion <= 9) {
  # Some android version-specific fixes:
  source.dirs."prebuilts/misc".postPatch = "ln -sf ${flex}/bin/flex linux-x86/flex/flex-2.5.39";
})
(mkIf (config.androidVersion >= 10) {
  source.dirs."build/make".patches = [
    ./readonly-fix.patch
    (pkgs.substituteAll {
      src = ./partition-size-fix.patch;
      inherit (pkgs) coreutils;
    })
    ./vendor_manifest-reproducible.patch
  ];

  # This one script needs python2. Used by sdk builds
  source.dirs."development".postPatch = ''
    substituteInPlace build/tools/mk_sources_zip.py \
      --replace "#!/usr/bin/python" "#!${pkgs.python2.interpreter}"
  '';
})
{
  envPackages = with pkgs; mkMerge ([
    # Check build/soong/ui/build/paths/config.go for a list of things that are needed
    [
      bc
      git
      gnumake
      jre8_headless
      lsof
      m4
      ncurses5
      openssl # Used in avbtool
      psmisc # for "fuser", "pstree"
      rsync
      unzip
      zip

      # Things not in build/soong/ui/build/paths/config.go
      nettools # Needed for "hostname" in build/soong/ui/build/sandbox_linux.go
      procps # Needed for "ps" in build/envsetup.sh
    ]
    (mkIf (config.androidVersion >= 10) [
      freetype # Needed by jdk9 prebuilt
      fontconfig

      python3
      python2 # device/generic/goldfish/tools/mk_combined_img.py still needs py2 :(
    ])
    (mkIf (config.androidVersion <= 9) [
      # stuff that was in the earlier buildenv. Not entirely sure everything here is necessary
      (androidPkgs.sdk (p: with p.stable; [ tools platform-tools ]))
      openssl.dev
      bison
      curl
      flex
      gcc
      gitRepo
      gnupg
      gperf
      imagemagick
      libxml2
      lzip
      lzop
      perl
      python2
      schedtool
      utillinux
      which
    ])
  ]);

  source.excludeGroups = mkDefault [
    "darwin" # Linux-only for now
    "mips" "hikey"
  ];
  source.includeGroups = mkIf (config.deviceFamily != null) (mkDefault [ config.deviceFamily ]);

  kernel.compiler = mkDefault "clang";
  kernel.clangVersion = mkDefault {
    "9" = "4393122";
    "10" = "r349610";
  }.${toString config.androidVersion};
  apex.enable = mkIf (config.androidVersion >= 10) (mkDefault true);
}
{
#  # Disable some unused directories to save time downloading / extracting
#  source.dirs = listToAttrs (map (dir: nameValuePair dir { enable = false; })
#    [ "developers/samples/android"
#      "developers/demos"
#
#      "device/generic/car"
##      "device/generic/qemu"
##      "prebuilts/qemu-kernel"
#      "prebuilts/android-emulator"
#
#      "device/linaro/bootloader/arm-trusted-firmware"
#      "device/linaro/bootloader/edk2"
#      "device/linaro/bootloader/OpenPlatformPkg"
#      "device/linaro/hikey"
#      "device/linaro/hikey-kernel"
#      "device/linaro"
#
#      "device/generic/mini-emulator-arm64"
#      "device/generic/mini-emulator-armv7-a-neon"
#      "device/generic/mini-emulator-mips"
#      "device/generic/mini-emulator-mips64"
#      "device/generic/mini-emulator-x86"
#      "device/generic/mini-emulator-x86_64"
#      "device/generic/mips"
#      "device/generic/mips64"
#      "device/google/accessory/arduino"
#      "device/google/accessory/demokit"
#      "device/google/atv"
#    ]);
}]
