# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf;
in
mkIf (config.androidVersion == 12) {
  source.dirs."build/make".patches = [
    ./build_make/0001-Readonly-source-fix.patch
  ];

  # This is the embedded python launcher that gets included in python apps by
  # soong.  We have to patchelf it before it is prepended to the zip of python
  # code.  See build/soong/python/builder.go. (merge_zips takes a --prepend
  # option that refers to this launcher)
  # This the prebuilt version of the launcher, which in Android 12 they use
  # instead of building from external/python/cpython3/android
  source.dirs."prebuilts/build-tools".postPatch = ''
    for file in linux-x86/bin/py*-launcher*; do
      patchelf --set-interpreter "${pkgs.stdenv.cc.bintools.dynamicLinker}" "$file"
    done
  '';

  #kernel.clangVersion = mkDefault "r370808";
}
