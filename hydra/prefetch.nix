{ nixdroid, pkgs ? import <unstable/nixpkgs> {}, ... }: with builtins; let
  h = import ./hydra.nix { isHydra = false; };
  nix-prefetch = pkgs.callPackage ../nix-prefetch.nix {};
in {
  prefetchers = let
    mapAttrsToList = f: attrs: map (k: f k attrs.${k}) (attrNames attrs);
    relevantAttrs = [ "repoRepoURL" "repoRepoRev" "referenceDir" "extraFlags" "localManifests" "device" "rev" "manifest" ]; # sha256
    filterRelevantAttrs = s: listToAttrs (concatMap (k: if any (x: x == k) relevantAttrs then [{ name = k; value = s.${k}; }] else []) (attrNames s));
    prefetchers = mapAttrsToList (x: y:
      "${nix-prefetch}/bin/nix-prefetch -f ${nixdroid}/repo2nix.nix --input json <<< '\"'\"'"  # Fuck escaping quotes
        + toJSON (mapAttrs (k: v: v.value) (filterRelevantAttrs h.jobsets."${x}".inputs)) + "'\"'\"'") h.jobsets;
  in
    # FIXME drop the NIX_PATH override
    pkgs.runCommand "nixdroid-prefetch.sh" {} ''
      echo $'#!/bin/sh
      export NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/unstable/
      ${concatStringsSep "\n" prefetchers}' > $out
      chmod +x $out
    '';
}
