{ nixdroid, pkgs ? import <unstable/nixpkgs> {}, ... }: with builtins; let
  h = import ./hydra.nix { isHydra = false; };
  nix-prefetch = pkgs.callPackage ../nix-prefetch.nix {};
in {
  prefetchers = let
    mapAttrsToList = f: attrs: map (k: f k attrs.${k}) (attrNames attrs);
    filterAttrs = pred: set: listToAttrs (concatMap (k: let v = set.${k}; in if pred k v then [ { name = k; value = v; } ] else []) (attrNames set));
    relevantAttrs = [ "repoRepoURL" "repoRepoRev" "referenceDir" "extraFlags" "localManifests" "device" "rev" "manifest" ]; # sha256
    filterRelevantAttrs = s: filterAttrs (k: v: any (x: x == k) relevantAttrs) s;
    filteredJobsets = filterAttrs (k: v: k != "prefetch") h.jobsets;
    prefetchers = mapAttrsToList (x: y:
      "${nix-prefetch}/bin/nix-prefetch -f ${nixdroid}/repo2nix.nix --input json <<< '\"'\"'"  # Fuck escaping quotes
        + toJSON (mapAttrs (k: v: v.value) (filterRelevantAttrs h.jobsets."${x}".inputs)) + "'\"'\"'" + " > ${h.jobsets.${x}.inputs.sha256Path.value}") filteredJobsets;
  in
    # FIXME drop the NIX_PATH override
    pkgs.runCommand "nixdroid-prefetch.sh" {} ''
      echo $'#!/bin/sh
      export NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/unstable/
      ${concatStringsSep "\n" prefetchers}' > $out
      chmod +x $out
    '';
}
