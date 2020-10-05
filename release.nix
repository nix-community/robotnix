let
  pkgs = import ./pkgs {};
  lib = pkgs.lib;
  robotnix = configuration: import ./default.nix { inherit configuration; };

  configs = (lib.listToAttrs (builtins.map (c: lib.nameValuePair "${c.flavor}-${c.device}" c) [
    { device="x86";        flavor="vanilla"; }
    { device="arm64";      flavor="vanilla"; }
    { device="marlin";     flavor="vanilla"; }
    { device="sailfish";   flavor="vanilla"; }
    { device="taimen";     flavor="vanilla"; }
    { device="walleye";    flavor="vanilla"; }
    { device="crosshatch"; flavor="vanilla"; }
    { device="blueline";   flavor="vanilla"; }
    { device="bonito";     flavor="vanilla"; }
    { device="sargo";      flavor="vanilla"; }
    { device="coral";      flavor="vanilla"; }
    { device="flame";      flavor="vanilla"; }
    { device="sunfish";    flavor="vanilla"; }

    { device="x86";        flavor="grapheneos"; }
    { device="arm64";      flavor="grapheneos"; }
    { device="taimen";     flavor="grapheneos"; }
    { device="walleye";    flavor="grapheneos"; }
    { device="crosshatch"; flavor="grapheneos"; }
    { device="blueline";   flavor="grapheneos"; }
    { device="bonito";     flavor="grapheneos"; }
    { device="sargo";      flavor="grapheneos"; }
    { device="coral";      flavor="grapheneos"; }
    { device="flame";      flavor="grapheneos"; }

    { device="marlin";     flavor="lineageos"; }
    { device="pioneer";    flavor="lineageos"; }

    { device="x86_64";     flavor="vanilla"; androidVersion=11; }
    { device="crosshatch"; flavor="vanilla"; androidVersion=11; }
    { device="x86_64";     flavor="grapheneos"; androidVersion=11; }
    { device="crosshatch"; flavor="grapheneos"; androidVersion=11; }
  ]));

  defaultBuild = robotnix { device="arm64"; flavor="vanilla"; };
in
{
  inherit (pkgs) diffoscope;

  testGenerateKeys = let
    generateKeysScript = (robotnix configs.grapheneos-crosshatch).generateKeysScript;
  in pkgs.runCommand "test-generate-keys" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    mkdir -p $out
    cd $out
    shellcheck ${generateKeysScript}
    ${generateKeysScript}
  '';

  check = lib.mapAttrs (name: c: (robotnix c).build.checkAndroid) configs;

  vanilla-arm64-generateKeysScript = defaultBuild.generateKeysScript;
  vanilla-arm64-ota = defaultBuild.ota;
  vanilla-arm64-factoryImg = defaultBuild.factoryImg;

  sdk = import ./sdk;

  grapheneos-emulator = (robotnix { device="x86"; flavor="grapheneos"; }).build.emulator;
  vanilla-emulator = (robotnix { device="x86"; flavor="vanilla"; }).build.emulator;
  danielfullmer-emulator = (robotnix { device="x86"; flavor="grapheneos"; imports = [ ./example.nix ]; apps.auditor.enable = lib.mkForce false; }).build.emulator;
} // (lib.mapAttrs (name: c: (robotnix c).img) configs)
