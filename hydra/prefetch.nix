{ nixdroid, ... }: with builtins; let
  h = import ./hydra.nix {};
in {
  prefetchers = derivation {
    name = "nixdroid-prefetch.sh";
    system = currentSystem;

    builder = "/bin/sh";
    args = let
      mapAttrsToList = f: attrs: map (k: f k attrs.${k}) (attrNames attrs);
      relevantAttrs = [ "repoRepoURL" "repoRepoRev" "referenceDir" "extraFlags" "localManifests" "device" "rev" "manifest" ]; # sha256
      filterRelevantAttrs = s: listToAttrs (concatMap (k: if any (x: x == k) relevantAttrs then [{ name = k; value = s.${k}; }] else []) (attrNames s));
      prefetchers = mapAttrsToList (x: y:
        "nix-prefetch -f ${nixdroid}/repo2nix.nix --input json <<< '\"'\"'"  # Fuck escaping quotes
          + toJSON (mapAttrs (k: v: v.value) (filterRelevantAttrs h.jobsets."${x}".inputs)) + "'\"'\"'") h.jobsets;
    in [ (toFile "builder.sh" ''
      echo $'#!/usr/bin/env nix-shell
      #!nix-shell -i sh -p nix-prefetch
      ${concatStringsSep "\n" prefetchers}' > $out
    '')];
  };
}
