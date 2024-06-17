# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ pkgs }:
with pkgs;
# TODO: Hack to workaround some android-related prebuilts that need to be fixup'd
# See 32-bit dependencies in src/build/install-build-deps-android
buildFHSUserEnv {
  name = "chromium-fhs";
  targetPkgs =
    pkgs: with pkgs; [
      # Stuff verified to be needed in chromium
      jdk8
      glibc_multi.dev # Needs unistd.h
      libkrb5.dev # Needs headers
      libkrb5
      ncurses5
      libxml2
    ];
  multiPkgs =
    pkgs: with pkgs; [
      zlib
      ncurses5
      gcc
      libgcc # Needed by their clang toolchain
    ];
}
