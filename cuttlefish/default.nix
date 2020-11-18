let
  pkgs = import ../pkgs {};
in {
  cuttlefish = pkgs.callPackage ./cuttlefish.nix { device = "cf_x86_phone"; };
  cuttlefish_arm64 = pkgs.pkgsCross.aarch64-multiplatform.callPackage ./cuttlefish.nix { device = "cf_arm64_phone"; };
}
