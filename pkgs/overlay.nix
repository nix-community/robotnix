self: super: {
  android-emulator = super.callPackage ./android-emulator {};

  android-prepare-vendor = super.callPackage ./android-prepare-vendor {};

  bundletool = super.callPackage ./bundletool {};

  diffoscope = (super.diffoscope.overrideAttrs (attrs: rec {
    patches = attrs.patches ++ [
      ./diffoscope/0001-comparators-android-Support-sparse-android-images.patch

      # Fix for https://salsa.debian.org/reproducible-builds/diffoscope/-/issues/255
      (super.fetchpatch {
        url = "https://salsa.debian.org/reproducible-builds/diffoscope/-/commit/6bf636c9f4e9f7d5b300723855bb2ac6cb9b11a1.patch";
        sha256 = "04m4f7z1lfbn2c3pkyhrb1ibafdllmqvf25swy31d19hi5ywgjy8";
      })
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

  # Robotnix helper derivations
  robotnix = super.callPackage ./robotnix {};
}
