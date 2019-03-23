{ nixdroid, pkgs ? import <nixpkgs> {}, ... }: with builtins; let
  h = import ./hydra.nix { isHydra = false; };
  nix-prefetch = pkgs.callPackage ../misc/nix-prefetch.nix {};
in {
  prefetchers = let
    mapAttrsToList = f: attrs: map (k: f k attrs.${k}) (attrNames attrs);
    filterAttrs = pred: set: listToAttrs (concatMap (k: let v = set.${k}; in if pred k v then [ { name = k; value = v; } ] else []) (attrNames set));
    relevantAttrs = [ "repoRepoURL" "repoRepoRev" "referenceDir" "extraFlags" "localManifests" "device" "rev" "manifest" ]; # sha256
    filterRelevantAttrs = s: filterAttrs (k: v: any (x: x == k) relevantAttrs) s;
    filteredJobsets = filterAttrs (k: v: k != "prefetch") h.jobsets;
    prefetchers = mapAttrsToList (x: y:
      "${nix-prefetch}/bin/nix-prefetch -f ${nixdroid}/repo2nix.nix --input json <<< '\"'\"'"  # Fuck escaping quotes
        + toJSON (mapAttrs (k: v: v.value) (filterRelevantAttrs h.jobsets."${x}".inputs)) + "'\"'\"'" + '' | tr -d "\n" > ${h.jobsets.${x}.inputs.sha256Path.value}'') filteredJobsets;
  in
    # FIXME drop the NIX_PATH override
    pkgs.runCommand "nixdroid-prefetch" {} ''
      mkdir -p $out/nix-support
      echo $'#!/bin/sh
      ${concatStringsSep "\n" prefetchers}' > $out/sh
      chmod +x $out/sh
      echo "file sh $out/sh" > $out/nix-support/hydra-build-products
    '';
}
