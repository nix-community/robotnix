# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  stdenv,
  lib,
  fetchurl,
  runCommand,
  writeText,
  writeShellScript,
  autoPatchelfHook,
  makeWrapper,
  glibc,
  libGL,
  libpulseaudio,
  zlib,
  ncurses5,
  nspr,
  fontconfig,
  nss,
  unzip,
  alsa-lib,
  libuuid,
  xlibs,
  dbus,
  xkeyboard_config,
  xorg,
  androidPkgs,
}:

let
  # TODO: Let user configure this
  defaultAVD = {
    AvdId = "Pixel2";
    PlayStore.enabled = "no";
    avd.ini.displayname = "Pixel2";
    avd.ini.encoding = "UTF-8";
    # Real Pixel2 ships with 32GB
    disk.dataPartition.size = "8096MB";
    fastboot.forceColdBoot = "no";
    hw.accelerometer = "yes";
    hw.audioInput = "yes";
    hw.battery = "yes";
    hw.camera.back = "emulated";
    hw.camera.front = "emulated";
    hw.cpu.ncore = 4;
    hw.dPad = "no";
    hw.device.hash2 = "MD5:bc5032b2a871da511332401af3ac6bb0";
    hw.device.manufacturer = "Google";
    hw.gps = "yes";
    hw.gpu.enabled = "yes";
    hw.gpu.mode = "auto";
    hw.initialOrientation = "Portrait";
    hw.keyboard = "yes";
    hw.mainKeys = "no";
    hw.ramSize = "4096";
    hw.sensors.orientation = "yes";
    hw.sensors.proximity = "yes";
    hw.trackBall = "no";
    runtime.network.latency = "none";
    runtime.network.speed = "full";
    vm.heapSize = 512;
    tag.display = "Robotnix";
    # Set some
    hw.lcd.density = 440;
    hw.lcd.height = 1920;
    hw.lcd.width = 1080;
    # Unused
    # hw.sdCard=yes
    # sdcard.size=512M

    tag.id = "robotnix";
    abi.type = "x86";
    hw.cpu.arch = "x86";
    image.sysdir."1" = "system-images/android/x86/";
  };

  # Turn an attrset into AVD text
  toAVD =
    conf:
    builtins.concatStringsSep "\n" (
      lib.collect builtins.isString (
        lib.mapAttrsRecursive (
          path: value: (builtins.concatStringsSep "." path) + "=" + (builtins.toString value)
        ) conf
      )
    );

  bindImg =
    {
      img,
      avd ? { },
    }:
    let
      fakeSdkRoot = runCommand "fake-sdk" { } ''
        mkdir -p $out/system-images/android
        ln -s ${img} $out/system-images/android/x86

        mkdir -p $out/platforms
        mkdir -p $out/platform-tools
      '';
      avdAttrs = lib.recursiveUpdate defaultAVD avd;
    in
    writeShellScript "bound-android-emulator" ''
      AVD=$(pwd)/avd
      mkdir -p $AVD/Pixel2.avd
      cp ${writeText "config.ini" (toAVD avdAttrs)}    $AVD/Pixel2.avd/config.ini
      echo "avd.ini.encoding=UTF-8"      > $AVD/Pixel2.ini
      echo "target=android-29"          >> $AVD/Pixel2.ini
      echo "path=$AVD/Pixel2.avd"       >> $AVD/Pixel2.ini
      chmod u+w $AVD/Pixel2.ini $AVD/Pixel2.avd/config.ini

      export ANDROID_SDK_ROOT=${fakeSdkRoot}
      export ANDROID_AVD_HOME=$AVD

      ${android-emulator}/emulator @Pixel2 -gpu swiftshader_indirect $@
    '';

  android-emulator = androidPkgs.packages.emulator.overrideAttrs (
    {
      passthru ? { },
      ...
    }:
    {
      passthru = passthru // {
        inherit bindImg;
      };
    }
  );
in
android-emulator
