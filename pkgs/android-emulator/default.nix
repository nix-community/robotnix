{ stdenv, lib, fetchurl, runCommand, writeText, writeShellScript,
  autoPatchelfHook, makeWrapper, glibc, libGL, libpulseaudio, zlib, ncurses5,
  nspr, fontconfig, nss, unzip, alsaLib, libuuid, xlibs, dbus, xkeyboard_config,
  xorg
}:

let
  # TODO: Let user configure this
  defaultAVD = {
    AvdId = "Pixel2";
    PlayStore.enabled = "no";
    avd.ini.displayname = "Pixel2";
    avd.ini.encoding = "UTF-8";
    # Real Pixel2 ships with 32GB
    disk.dataPartition.size = "4096MB";
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
  toAVD = conf: builtins.concatStringsSep "\n"
    (lib.collect builtins.isString
      (lib.mapAttrsRecursive
        (path: value: (builtins.concatStringsSep "." path) + "=" + (builtins.toString value))
        conf));

  android-emulator = stdenv.mkDerivation rec {
    pname = "android-emulator";
    version = "3.0.5";

    # https://androidstudio.googleblog.com/2020/03/emulator-3005-canary.html
    # From https://dl.google.com/android/repository/repository2-1.xml
    src = fetchurl {
      url = "https://dl.google.com/android/repository/emulator-linux-6306047.zip";
      sha256 = "0crgcawp366mql9zhr5xp4vlfklijrnp9ii706cssmlc3sz5jspz";
    };

    buildInputs = [
      unzip autoPatchelfHook makeWrapper
      glibc stdenv.cc.cc nss libGL libpulseaudio zlib ncurses5 nspr fontconfig
      alsaLib libuuid
    ] ++ (with xlibs; [
      libX11 libXext libXdamage libXfixes libXcomposite libXcursor libXi
      libXrender libXtst libxcb
    ]);

    # Some of this is from nixpkgs android sdk emulator derivation
    postFixup = ''
      # Wrap emulator so that it can load libdbus-1.so at runtime and it no longer complains about XKB keymaps
      wrapProgram $out/emulator \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ dbus ]} \
        --set QT_XKB_CONFIG_ROOT ${xkeyboard_config}/share/X11/xkb \
        --set QTCOMPOSE ${xorg.libX11.out}/share/X11/locale
    '';
    installPhase = ''
      cp -r --reflink=auto . $out/
    '';

    passthru = {
      bindImg = img: let
        fakeSdkRoot = runCommand "fake-sdk" {} ''
          mkdir -p $out/system-images/android
          ln -s ${img} $out/system-images/android/x86

          mkdir -p $out/platforms
          mkdir -p $out/platform-tools
        '';
      in writeShellScript "bound-android-emulator" ''
        AVD=$(pwd)/avd
        mkdir -p $AVD/Pixel2.avd
        cp ${writeText "config.ini" (toAVD defaultAVD)}    $AVD/Pixel2.avd/config.ini
        echo "avd.ini.encoding=UTF-8"      > $AVD/Pixel2.ini
        echo "target=android-29"          >> $AVD/Pixel2.ini
        echo "path=$AVD/Pixel2.avd"       >> $AVD/Pixel2.ini
        chmod u+w $AVD/Pixel2.ini $AVD/Pixel2.avd/config.ini

        export ANDROID_SDK_ROOT=${fakeSdkRoot}
        export ANDROID_AVD_HOME=$AVD

        ${android-emulator}/emulator @Pixel2 -gpu swiftshader_indirect $@
      '';
    };
  };
in android-emulator
