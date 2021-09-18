# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf;
in
mkIf (config.androidVersion == 12) (mkMerge [
{
  source.dirs."build/make".patches = [
    ./build_make/0001-Readonly-source-fix.patch
  ];

  # This one script needs python2. Used by sdk builds
  source.dirs."development".postPatch = ''
    substituteInPlace build/tools/mk_sources_zip.py \
      --replace "#!/usr/bin/python" "#!${pkgs.python2.interpreter}"
  '';

  #kernel.clangVersion = mkDefault "r370808";
}
])
