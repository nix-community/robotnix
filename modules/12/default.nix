# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf;
in
mkIf (config.androidVersion == 12) {
  source.dirs."build/make".patches = [
    ./build_make/0001-Readonly-source-fix.patch
    ./build_make/0001-Add-vendor-bootconfig.img-to-target-files-package.patch
  ];


  # Disable clang-tidy checks. android-12.0.0_r2 fails when building cuttlefish img
  source.dirs."system/incremental_delivery".postPatch = ''
    substituteInPlace incfs/Android.bp \
      --replace "tidy: true" "tidy: false"

    substituteInPlace libdataloader/Android.bp \
      --replace "tidy: true" "tidy: false"
  '';

  #kernel.clangVersion = mkDefault "r370808";
}
