let
  checkConfig = configuration:
    (import ./default.nix { inherit configuration; }).source.jsonFile;
  grapheneDevices = [
    "taimen" "walleye"
    "crosshatch" "blueline"
    "bonito" "sargo"
  ];
  devices = grapheneDevices ++ [
    "marlin" "sailfish"
    "coral" "flame" # No android-prepare-vendor yet
  ];
in builtins.map (c: checkConfig c) (
  (builtins.map (d: { device = d; }) devices) ++
  (builtins.map (d: { device = d; flavor="grapheneos"; }) grapheneDevices)
)
