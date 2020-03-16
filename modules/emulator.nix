{ config, pkgs, lib, ... }:

# TODO: This module is still not working

#        --set ANDROID_PRODUCT_OUT ${config.build.android}

with lib;
let
  platform-tools-aosp = import ../default.nix {
    configuration = {
      buildProduct = "sdk";
      variant = "eng";
    };
  };
  fakeAndroidBuildDirs = pkgs.linkFarm "fake-android-build-dirs"
    #(map (name: { inherit name; path = platform-tools-aosp.source.dirs.${name}.contents; })
    (map (name: { inherit name; path = config.source.dirs.${name}.contents; })
    [ "prebuilts/qemu-kernel" "development" ]);
in
{
  config.build.emulator = pkgs.stdenv.mkDerivation {
    name = "emulator-${config.buildNumber}";
    #src = platform-tools-aosp.source.dirs."prebuilts/android-emulator".contents;
    src = config.source.dirs."prebuilts/android-emulator".contents;
    buildInputs = with pkgs; [ autoPatchelfHook makeWrapper ] ++
      [ glibc xlibs.libX11 xlibs.libXext xlibs.libXdamage xlibs.libXfixes
        xlibs.libxcb libGL libpulseaudio zlib ncurses5 nspr fontconfig
        nss stdenv.cc.cc
      ];

    # Some of this is from nixpkgs android sdk emulator derivation
    postFixup = ''
#      addAutoPatchelfSearchPath $packageBaseDir/lib
#      addAutoPatchelfSearchPath $packageBaseDir/lib64
#      addAutoPatchelfSearchPath $packageBaseDir/lib64/qt/lib
#      autoPatchelf $out

      # Wrap emulator so that it can load libdbus-1.so at runtime and it no longer complains about XKB keymaps
      wrapProgram $out/emulator \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.dbus ]} \
        --set QT_XKB_CONFIG_ROOT ${pkgs.xkeyboard_config}/share/X11/xkb \
        --set QTCOMPOSE ${pkgs.xorg.libX11.out}/share/X11/locale \
        --set ANDROID_BUILD_TOP ${fakeAndroidBuildDirs}
    '';
    installPhase = ''
      cp -r --reflink=auto linux-x86_64 $out/
    '';
  };

  config.build.emulatorImage = config.build.mkAndroid {
    name = "robotnix-emulatorimage";
    makeTargets = [];
    # Kinda ugly to just throw all this in $bin/
    # Don't do patchelf in this derivation, just in case it fails we'd still like to have cached results
    # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
    installPhase = ''
      mkdir -p $out
      export ANDROID_PRODUCT_OUT=$(cat ANDROID_PRODUCT_OUT)

      # Just grab top-level build products (for emulator, not recursive) + target_files
      find $ANDROID_PRODUCT_OUT -maxdepth 1 -type f | xargs -I {} cp --reflink=auto {} $out/
      mkdir -p $out/system
      cp $ANDROID_PRODUCT_OUT/system/build.prop $out/system
      cp $ANDROID_PRODUCT_OUT/VerifiedBootParams.textproto $out/
    '';
  };
}
