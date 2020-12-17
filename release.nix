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

  builtConfigs = lib.mapAttrs (name: c: robotnix c) configs;

  defaultBuild = robotnix { device="arm64"; flavor="vanilla"; };
in
{
  inherit (pkgs) diffoscope;

  testGenerateKeys = let
    inherit ((robotnix { device="crosshatch"; flavor="vanilla"; }))
      generateKeysScript verifyKeysScript;
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

  imgs = lib.recurseIntoAttrs (lib.mapAttrs (name: c: c.img) builtConfigs);

  # For testing instantiation
  vanilla-arm64 = lib.recurseIntoAttrs {
    inherit (defaultBuild)
      targetFiles ota img factoryImg bootImg otaDir
      releaseScript;
  };

  sdk = import ./sdk;

  grapheneos-emulator = (robotnix { device="x86"; flavor="grapheneos"; }).emulator;
  vanilla-emulator = (robotnix { device="x86"; flavor="vanilla"; }).emulator;
  danielfullmer-emulator = (robotnix { device="x86"; flavor="grapheneos"; imports = [ ./example.nix ]; apps.auditor.enable = lib.mkForce false; }).emulator;

  # Stuff to upload to binary cache
  cached = lib.recurseIntoAttrs {
    browsers = lib.recurseIntoAttrs {
      inherit ((robotnix { device = "arm64"; flavor="vanilla"; }).config.build)
        chromium bromite;

      inherit ((robotnix { device = "arm64"; flavor="grapheneos"; }).config.build)
        vanadium;
    };

    kernels = lib.recurseIntoAttrs
      (lib.mapAttrs (name: c: c.config.build.kernel)
        (lib.filterAttrs (name: c: c.config.kernel.useCustom) builtConfigs));
  };
}
