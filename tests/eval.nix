# To run these tests:
# nix-instantiate --eval --strict ./eval.nix
# if the resulting list is empty, all tests passed

let
  pkgs = import ../pkgs { };
  lib = pkgs.lib;
  robotnixSystem = configuration: import ../default.nix { inherit configuration pkgs; };
in

lib.runTests {
  testSourceMountPoints = {
    expr =
      let
        dirs = [
          "a"
          "a/b"
          "a/c"
          "b/d"
          "b/e"
        ];
      in
      lib.filterAttrs (n: v: lib.elem n dirs) (
        (lib.mapAttrs (name: dir: dir.postPatch))
          (robotnixSystem { source.dirs = lib.genAttrs dirs (dir: { }); }).config.source.dirs
      );
    expected = {
      "a" = ''
        mkdir -p b
        mkdir -p c
      '';
      "a/b" = "";
      "a/c" = "";
      "b/d" = "";
      "b/e" = "";
    };
  };
}
