{ ... }@args:

let
  nixpkgs = builtins.fetchTarball {
    # nixos-20.03 channel. Latest as of 2020-05-03
    url = "https://github.com/nixos/nixpkgs/archive/ab3adfe1c769c22b6629e59ea0ef88ec8ee4563f.tar.gz";
    sha256 = "1m4wvrrcvif198ssqbdw897c8h84l0cy7q75lyfzdsz9khm1y2n1";
  };

  overlay = self: super: {
    androidPkgs = import (builtins.fetchTarball {
      url = "https://github.com/tadfisher/android-nixpkgs/archive/b1ade09a9ea7f92c15a0a572c6a4b1a813c0cd96.tar.gz";
      sha256 = "15zb11pcl1qrw34vq6j0ckq025nhksins12rzm35bs9j6hnq1cna";
    }) { pkgs = self; };

    android-emulator = super.callPackage ./android-emulator {};

    android-prepare-vendor = super.callPackage ./android-prepare-vendor {};

    bundletool = super.callPackage ./bundletool {};

    diffoscope = (super.diffoscope.overrideAttrs (attrs: rec {
      version = "144";
      src = super.fetchurl {
        url    = "https://diffoscope.org/archive/diffoscope-${version}.tar.bz2";
        sha256 = "1n916k6z35c8ffksjjglkbl52jjhjv3899w230sg7k4ayzylj6zi";
      };
      patches = attrs.patches ++ [
        ./diffoscope/0001-comparators-android-Support-sparse-android-images.patch
        ./diffoscope/0002-libguestfs-mount-readonly.patch
        ./diffoscope/0003-HACK-prefix-tool-names.patch
      ];
      pythonPath = attrs.pythonPath ++ [ super.simg2img super.zip ];
    })).override {
      python3Packages = super.python3Packages.override {
        overrides = pythonSelf: pythonSuper: {
          guestfs = pythonSuper.guestfs.override { libguestfs = super.libguestfs-with-appliance; };
        };
      };
      binutils-unwrapped = super.pkgsCross.aarch64-multiplatform.buildPackages.binutils-unwrapped;
      enableBloat = true;
    };

    cipd = super.callPackage ./cipd {};
    fetchcipd = super.callPackage ./cipd/fetchcipd.nix {};

    fetchgerritpatchset = super.callPackage ./fetchgerritpatchset {};

    nix-prefetch-git = super.callPackage ./nix-prefetch-git {};
  };
in
  import nixpkgs (args // {
    overlays = [ overlay ];
    config = { android_sdk.accept_license=true; };
  })
