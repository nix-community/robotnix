{ config, pkgs, lib, ... }:

with lib;
mkIf (config.androidVersion >= 10) {
  source.dirs."build/make".patches = [
    ./build-make-readonly-source.patch
    (pkgs.substituteAll { # Alternative fix was upstreamed in https://android-review.googlesource.com/c/platform/build/+/1269603
      src = ./build-make-partition-size-fix.patch;
      inherit (pkgs) coreutils;
    })
    ./build-make-vendor_manifest-reproducible.patch
    ./build-make-userdata-cache-uuid-reproducible.patch
  ];

  # This one script needs python2. Used by sdk builds
  source.dirs."development".postPatch = ''
    substituteInPlace build/tools/mk_sources_zip.py \
      --replace "#!/usr/bin/python" "#!${pkgs.python2.interpreter}"
  '';

  apex.enable = mkDefault true;

  kernel.clangVersion = mkDefault "r349610";
}
