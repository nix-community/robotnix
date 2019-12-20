(import ./default.nix {
  configuration = { buildProduct = "sdk"; };
}).build.sdk
