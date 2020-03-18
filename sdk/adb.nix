let
  pkgs = import ../pkgs.nix {};
  adb = (import ../default.nix {
    configuration = {
      buildProduct = "sdk";
      variant = "eng";
      source.jsonFile = ./platform-tools-29.0.5.json; # TODO: 29.0.6 is out now
    };
  }).build.mkAndroid {
    name = "adb";
    makeTargets = [ "adb" "fastboot" ];
    installPhase = ''
      mkdir -p $out
      cp $OUT_DIR/host/linux-x86/bin/{adb,fastboot} $out/
    '';
  };
in
  pkgs.runCommandCC "adb" { nativeBuildInputs = [ pkgs.autoPatchelfHook ]; } ''
    mkdir -p $out/bin
    cp ${adb}/* $out/bin/
    chmod u+w $out/bin/*
    autoPatchelf $out/bin/*
  ''
