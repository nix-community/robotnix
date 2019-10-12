let
  checkConfig = configuration:
    (import ./default.nix { inherit configuration; }).build.checkAndroid;
  devices = [
    "marlin" "sailfish"
    "taimen" "walleye"
    "crosshatch" "blueline"
    "bonito" "sargo"
  ];
in builtins.map (c: checkConfig c) (
  (builtins.map (d: { device = d; }) devices) ++
  (builtins.map (d: { device = d; flavor="grapheneos"; }) devices) ++
  [ { device="marlin"; imports = [ ./example.nix ]; }
    { device="crosshatch"; imports = [ ./example.nix ]; }
  ]
)
# A total of 18 configurations above. Each takes about 3-4 minutes to fake
# "build" for a total estimated checking time of about an hour if run
# sequentially
