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
    #"coral" "flame" # No android-prepare-vendor yet

    { device="x86";        flavor="grapheneos"; }
    { device="arm64";      flavor="grapheneos"; }
    { device="taimen";     flavor="grapheneos"; }
    { device="walleye";    flavor="grapheneos"; }
    { device="crosshatch"; flavor="grapheneos"; }
    { device="blueline";   flavor="grapheneos"; }
    { device="bonito";     flavor="grapheneos"; }
    { device="sargo";      flavor="grapheneos"; }
  ])) // {
    danielfullmer = { # My personal config
      device="crosshatch";
      flavor="grapheneos";
      imports = [ ./example.nix ];
      # TODO: This will only evaluate on my computer...
      keyStorePath = "/var/secrets/android-keys";
      signBuild = true;
    };
  };
in
{
  inherit (pkgs) diffoscope;

  # A total of 16 configurations above. Each takes about 3-4 minutes to fake
  # "build" for a total estimated checking time of about an hour if run
  # sequentially
  check = lib.mapAttrs (name: c: (robotnix c).build.checkAndroid) configs;

  sdk = import ./sdk;

  grapheneos-emulator = (robotnix { device="x86"; flavor="grapheneos"; }).build.emulator;
  vanilla-emulator = (robotnix { device="x86"; flavor="grapheneos"; }).build.emulator;
  danielfullmer-emulator = (robotnix { device="x86"; flavor="grapheneos"; imports = [ ./example.nix ]; apps.auditor.enable = lib.mkForce false; }).build.emulator;
} // (lib.mapAttrs (name: c: (robotnix c).img) configs)
