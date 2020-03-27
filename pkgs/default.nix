{ ... }@args:

let
  nixpkgs = builtins.fetchTarball {
    # nixos-19.09 channel. Latest as of 2019-11-11
    url = "https://github.com/nixos/nixpkgs/archive/2d896998dc9b1b0daeb8a180dc170733f1225678.tar.gz";
    sha256 = "1vj3bwljkh55si4qjx52zgw7nfy6mnf324xf1l2i5qffxlh7qxb6";
  };

  overlay = self: super: {
    androidPkgs = import (builtins.fetchTarball {
      url = "https://github.com/tadfisher/android-nixpkgs/archive/d3f24c3618c3d3ecdc32d164d4294578ae369e9d.tar.gz";
      sha256 = "0d0n8am9k2cwca7kf64xi7ypriy8j1h3bc2jzyl8qakpfdcp19np";
    }) { pkgs = self; };

    buildGradle = super.callPackage ./gradle-env.nix {};

    bundletool = super.callPackage ./bundletool {};

    diffoscope = (super.diffoscope.overrideAttrs (attrs: {
      patches = attrs.patches ++ [
        ./diffoscope/0001-comparators-android-Support-sparse-android-images.patch
        ./diffoscope/arch-hack.patch
      ];
      pythonPath = attrs.pythonPath ++ [ super.simg2img ];
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
  };
in
  import nixpkgs (args // {
    overlays = [ overlay ];
    config = { android_sdk.accept_license=true; };
  })
