{ ... }@args:

let
  nixpkgs = builtins.fetchTarball {
    # nixos-20.09 channel. Latest as of 2020-10-30
    url = "https://github.com/nixos/nixpkgs/archive/9bf04bc90bf634c1f20ce453b53cf68963e02fa1.tar.gz";
    sha256 = "0ns404k2r5m054zm93a616x58cvj66r82phmm7bszpf5370brqg5";
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
      patches = attrs.patches ++ [
        ./diffoscope/0001-comparators-android-Support-sparse-android-images.patch
        ./diffoscope/0002-HACK-prefix-tool-names.patch
      ];
      pythonPath = attrs.pythonPath ++ [ super.simg2img super.zip ];
      doCheck = false;
      doInstallCheck = false;
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

    ###

    inherit (super.callPackage ./build-tools {})
      build-tools
      apksigner
      signApk;
  };
in
  import nixpkgs (args // {
    overlays = [ overlay ];
    config = { android_sdk.accept_license=true; };
  })
