{ ... }@args:

let
  nixpkgs = builtins.fetchTarball {
    # nixos-20.03 channel. Latest as of 2020-05-03
    url = "https://github.com/nixos/nixpkgs/archive/ab3adfe1c769c22b6629e59ea0ef88ec8ee4563f.tar.gz";
    sha256 = "1m4wvrrcvif198ssqbdw897c8h84l0cy7q75lyfzdsz9khm1y2n1";
  };

  overlay = self: super: {
    androidPkgs = import (builtins.fetchTarball {
      url = "https://github.com/tadfisher/android-nixpkgs/archive/d3f24c3618c3d3ecdc32d164d4294578ae369e9d.tar.gz";
      sha256 = "0d0n8am9k2cwca7kf64xi7ypriy8j1h3bc2jzyl8qakpfdcp19np";
    }) { pkgs = self; };

    android-emulator = super.callPackage ./android-emulator {};

    buildGradle = super.callPackage ./gradle-env.nix {};

    bundletool = super.callPackage ./bundletool {};

    diffoscope = (super.diffoscope.overrideAttrs (attrs: rec {
      version = "142";
      src = super.fetchurl {
        url    = "https://diffoscope.org/archive/diffoscope-${version}.tar.bz2";
        sha256 = "0c6lvppghw9ynjg2radr8z3fc6lpgmgwr6kxyih7q4rxqf4gfv6i";
      };
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
