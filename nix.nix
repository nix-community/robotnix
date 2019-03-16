{ pkgs ? import <unstable> {} }:
let
  patchedNix = pkgs.nixUnstable.overrideAttrs (oA: {
    patches = with pkgs; [
      (fetchpatch {
        url = https://patch-diff.githubusercontent.com/raw/NixOS/nix/pull/2582.patch;
        sha256 = "1jx6aplbp4rarm1qckirhmnbwy8xqmjk7xa41qjffjaqccj2ll78";
      })
      (fetchpatch {
        url = https://github.com/ajs124/nix/commit/74e05870a1e97682413eb09d804ccbdb289c1a6d.patch;
        sha256 = "165b9zsdijkpw2x3ighmkyj9p339rk4sxapr6917y9y4bmaqnrxn";
      })
      (fetchpatch {
        url = https://github.com/ajs124/nix/commit/e3e6c1a8afceae4750223e119319da5a5b62b01e.patch;
        sha256 = "0x5cpz7zb9vbayi6sqgpvhpn2p81hg87aaziawx7p64akfqgmqk3";
      })
    ];
  });
in patchedNix
