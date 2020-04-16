let
  pkgs = import ../pkgs {};
  adb = (import ../default.nix {
    configuration = {
      buildProduct = "sdk";
      variant = "eng";
      source.dirs = builtins.fromJSON (builtins.readFile ../flavors/vanilla/android-10.0.0_r33.json);
    };
  }).build.mkAndroid {
    name = "adb";
    makeTargets = [ "adb" "fastboot" ];
    installPhase = ''
      mkdir -p $out
      cp out/host/linux-x86/bin/{adb,fastboot} $out/
    '';
  };
in
  pkgs.runCommandCC "adb" { nativeBuildInputs = [ pkgs.autoPatchelfHook ]; } ''
    mkdir -p $out/bin
    cp ${adb}/* $out/bin/
    chmod u+w $out/bin/*
    autoPatchelf $out/bin/*
  ''
