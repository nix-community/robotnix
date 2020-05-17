{ config, pkgs, lib, ... }:

with lib;
let
  # Some mostly-unique data used as input for filesystem UUIDs, hash_seeds, and AVB salt.
  # TODO: Maybe include all source hashes except from build/make to avoid infinite recursion?
  hash = builtins.hashString "sha256" "${config.buildNumber} ${builtins.toString config.buildDateTime}";
in
mkIf (config.androidVersion >= 10) {
  source.dirs."build/make".patches = [
    ./build_make/0001-Readonly-source-fix.patch
    (pkgs.substituteAll {
      src = ./build_make/0002-Partition-size-fix.patch;
      inherit (pkgs) coreutils;
    })
    ./build_make/0003-Make-vendor_manifest.xml-reproducible.patch
    (pkgs.substituteAll {
      src = ./build_make/0004-Set-uuid-and-hash_seed-for-userdata-and-cache.patch;
      inherit hash;
    })
  ];

  # This one script needs python2. Used by sdk builds
  source.dirs."development".postPatch = ''
    substituteInPlace build/tools/mk_sources_zip.py \
      --replace "#!/usr/bin/python" "#!${pkgs.python2.interpreter}"
  '';

  apex.enable = mkDefault true;

  kernel.clangVersion = mkDefault "r349610";
}
