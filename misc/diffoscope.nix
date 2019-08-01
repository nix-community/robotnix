let
  pkgs = import <nixpkgs> {};
  python3Packages = pkgs.python3Packages.override {
    overrides = self: super: {
      guestfs = super.guestfs.override { libguestfs = pkgs.libguestfs-with-appliance; };
    };
  };
in
(pkgs.diffoscope.overrideAttrs (attrs: {
  patches = attrs.patches ++ [
    ./0001-comparators-android-Support-sparse-android-images.patch
    ./diffoscope-arch-hack.patch
  ];
  pythonPath = attrs.pythonPath ++ [ pkgs.simg2img ];
})).override {
  inherit python3Packages;
  binutils-unwrapped = pkgs.pkgsCross.aarch64-multiplatform.buildPackages.binutils-unwrapped;
  enableBloat = true;
}
