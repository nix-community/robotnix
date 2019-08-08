let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/525eaf407d4edb329ea48f6dc9c6590fb73c779a.tar.gz";
    sha256 = "0l2hvrpsvnlv2ly6il4n5gzn673zjlssrwi0ryvla42i06grqpis";
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
