let
  pkgs = import ./pkgs {};
  lib = pkgs.lib;
  robotnix = configuration: import ./default.nix { inherit configuration; };

  configs = (lib.listToAttrs (builtins.map (c: lib.nameValuePair "${c.flavor}-${c.device}" c) [
    { device="x86_64";     flavor="vanilla"; }
    { device="arm64";      flavor="vanilla"; }
    { device="marlin";     flavor="vanilla"; androidVersion=10; } # Out-of-date
    { device="sailfish";   flavor="vanilla"; androidVersion=10; } # Out-of-date
    { device="taimen";     flavor="vanilla"; }
    { device="walleye";    flavor="vanilla"; }
    { device="crosshatch"; flavor="vanilla"; }
    { device="blueline";   flavor="vanilla"; }
    { device="bonito";     flavor="vanilla"; }
    { device="sargo";      flavor="vanilla"; }
    { device="coral";      flavor="vanilla"; }
    { device="flame";      flavor="vanilla"; }
    { device="sunfish";    flavor="vanilla"; }

    { device="x86_64";     flavor="grapheneos"; }
    { device="arm64";      flavor="grapheneos"; }
    { device="crosshatch"; flavor="grapheneos"; }
    { device="blueline";   flavor="grapheneos"; }
    { device="bonito";     flavor="grapheneos"; }
    { device="sargo";      flavor="grapheneos"; }
    { device="coral";      flavor="grapheneos"; }
    { device="flame";      flavor="grapheneos"; }
    { device="sunfish";    flavor="grapheneos"; }

    { device="marlin";     flavor="lineageos"; }
    { device="pioneer";    flavor="lineageos"; }

  ]));

  defaultBuild = robotnix { device="arm64"; flavor="vanilla"; };
in
{
  inherit (pkgs) diffoscope;

  testGenerateKeys = let
    generateKeysScript = (robotnix configs.grapheneos-crosshatch).generateKeysScript;
    verifyKeysScript = (robotnix configs.grapheneos-crosshatch).verifyKeysScript;
  in pkgs.runCommand "test-generate-keys" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    mkdir -p $out
    cd $out
    shellcheck ${generateKeysScript}
    shellcheck ${verifyKeysScript}

    ${verifyKeysScript} $PWD && exit 1 || true # verifyKeysScript should fail if we haven't generated keys yet
    ${generateKeysScript} $PWD
    ${verifyKeysScript} $PWD
  '';

  check = lib.mapAttrs (name: c: (robotnix c).config.build.checkAndroid) configs;

  vanilla-arm64-generateKeysScript = defaultBuild.generateKeysScript;
  vanilla-arm64-ota = defaultBuild.ota;
  vanilla-arm64-factoryImg = defaultBuild.factoryImg;

  sdk = import ./sdk;

  grapheneos-emulator = (robotnix { device="x86"; flavor="grapheneos"; }).emulator;
  vanilla-emulator = (robotnix { device="x86"; flavor="vanilla"; }).emulator;
  danielfullmer-emulator = (robotnix { device="x86"; flavor="grapheneos"; imports = [ ./example.nix ]; apps.auditor.enable = lib.mkForce false; }).emulator;
} // (lib.mapAttrs (name: c: (robotnix c).img) configs)
