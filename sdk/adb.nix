# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

let
  pkgs = import ../pkgs { };
  androidHostOut = "out/host/${
    if pkgs.stdenv.hostPlatform.isDarwin then "darwin-x86" else "linux-x86"
  }";
  adb =
    (import ../default.nix {
      inherit pkgs;
      configuration = {
        productName = "sdk";
        variant = "eng";
        source.dirs = builtins.fromJSON (builtins.readFile ./repo-platform-tools-30.0.0.json);
      };
    }).build.mkAndroid
      {
        name = "adb";
        makeTargets = [
          "adb"
          "fastboot"
        ];
        installPhase = ''
          mkdir -p $out
          cp ${androidHostOut}/bin/{adb,fastboot} $out/
        '';
      };
in
pkgs.runCommandCC "adb" { nativeBuildInputs = [ pkgs.autoPatchelfHook ]; } ''
  mkdir -p $out/bin
  cp ${adb}/* $out/bin/
  chmod u+w $out/bin/*
  autoPatchelf $out/bin/*
''
