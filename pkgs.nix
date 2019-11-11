let
  nixpkgs = builtins.fetchTarball {
    # nixos-19.09 channel. Latest as of 2019-11-11
    url = "https://github.com/nixos/nixpkgs/archive/2d896998dc9b1b0daeb8a180dc170733f1225678.tar.gz";
    sha256 = "1vj3bwljkh55si4qjx52zgw7nfy6mnf324xf1l2i5qffxlh7qxb6";
  };

  # Hack since I can't figure out how to overide the androidenv stuff with an overlay.
  # Needed for gradle builds
  # TODO: Should this patch be upstreamed?
  patchedNixpkgs = (import nixpkgs {}).runCommand "nixpkgs-patched" {} ''
    cp -r ${nixpkgs} $out
    chmod -R +w $out
    patch -d $out -p1 < ${./patches/nixpkgs-licenses.patch}
  '';

  overlay = self: super: {
    diffoscope = (super.diffoscope.overrideAttrs (attrs: {
      patches = attrs.patches ++ [
        ./patches/0001-comparators-android-Support-sparse-android-images.patch
        ./patches/diffoscope-arch-hack.patch
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
  };
in
  import patchedNixpkgs {
    overlays = [ overlay ];
    config = { android_sdk.accept_license=true; };
  }
