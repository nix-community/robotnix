{ nixdroid, ... }: with builtins;
let
  h = import ./hydra.nix {};
in {
  jobsets = derivation {
    name = "spec.json";
    system = currentSystem;

    builder = "/bin/sh";
    args = [ (toFile "builder.sh" ''
      echo '${toJSON (mapAttrs (k: v: h.defaultJobset // v) h.jobsets)}' > $out
    '') ];
  };
}
