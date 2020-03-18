let
  checkConfig = configuration:
    (import ./default.nix { inherit configuration; }).build.checkAndroid;
  devices = [
    "taimen" "walleye"
    "crosshatch" "blueline"
    "bonito" "sargo"
    #"coral" "flame" # No android-prepare-vendor yet
  ];
in (builtins.map (c: checkConfig c) (
  (builtins.map (d: { device = d; }) (devices ++ [ "marlin" "sailfish" ])) ++
  (builtins.map (d: { device = d; flavor="grapheneos"; }) devices) ++
  [ { device="crosshatch"; flavor="grapheneos"; imports = [ ./example.nix ]; } ]
))# ++
#[ (import ./default.nix { configuration = { buildProduct = "sdk"; }; }).build.checkSdk ]
# A total of 16 configurations above. Each takes about 3-4 minutes to fake
# "build" for a total estimated checking time of about an hour if run
# sequentially
