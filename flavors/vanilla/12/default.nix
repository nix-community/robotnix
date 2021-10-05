# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault;

  inherit (import ./supported-devices.nix { inherit lib config; })
    supportedDeviceFamilies phoneDeviceFamilies;
in
(mkIf (config.flavor == "vanilla" && config.androidVersion == 12) {
  source.manifest.rev = mkDefault "android-s-beta-3";
  buildDateTime = mkDefault 1626302605;

  # Includes a fix for:
  # error: build/soong/java/core-libraries/Android.bp:130:1: module "legacy.core.platform.api.stubs" already defined
  #        libcore/mmodules/core_platform_api/Android.bp:182:1 <-- previous definition here
  # error: build/soong/java/core-libraries/Android.bp:146:1: module "stable.core.platform.api.stubs" already defined
  #        libcore/mmodules/core_platform_api/Android.bp:198:1 <-- previous definition here
  # error: build/soong/java/core-libraries/Android.bp:164:1: module "legacy-core-platform-api-stubs-system-modules" already defined
  #        libcore/mmodules/core_platform_api/Android.bp:216:1 <-- previous definition here
  # error: build/soong/java/core-libraries/Android.bp:180:1: module "stable-core-platform-api-stubs-system-modules" already defined
  #        libcore/mmodules/core_platform_api/Android.bp:232:1 <-- previous definition here
  # error: libcore/JavaLibrary.bp:994:1: module "core.current.stubs" already defined
  #        build/soong/java/core-libraries/Android.bp:27:1 <-- previous definition here
  # error: libcore/JavaLibrary.bp:1015:1: module "core-current-stubs-for-system-modules" already defined
  #        build/soong/java/core-libraries/Android.bp:48:1 <-- previous definition here
  # error: libcore/JavaLibrary.bp:1041:1: module "core-current-stubs-system-modules" already defined
  #        build/soong/java/core-libraries/Android.bp:74:1 <-- previous definition here
  source.dirs."libcore".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/libcore";
    rev = "fdef4f02eb440abfcb6052c49b1bff8a0b117a97";
    sha256 = "1xplnsbsdvzjnfm8vir9dmf2l5zvp3rwfd9lsiy3y03j12jdj8h7";
  };

  # Needed for various compile errors:
  source.dirs."packages/modules/NeuralNetworks".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/packages/modules/NeuralNetworks";
    rev = "2ad9cac21a32fb04f85269192d31a3afd8e0e7b1";
    sha256 = "16gqbnhq5fyn243jqcbh74slrm99fb2dg7axjx5pl3fviylg2lrr";
  };

  # Missing from manifest
  source.dirs."external/rust/crates/flate2".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/external/rust/crates/flate2";
    rev = "d3264146a47db69fefe423e81402497183d820c4";
    sha256 = "08f464gih4qnlh1sy8gy7a2mxyya2b39sp2ihwsh1yrbsy2zg0jh";
  };
  source.dirs."external/rust/crates/base64".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/external/rust/crates/base64";
    rev = "7339bd125207a571531076675fc190aaa4bccb17";
    sha256 = "0831gb26mp6y2j7ywfs3k611dnqbnlprkx4w5v20y84ncmipr7n6";
  };
  source.dirs."external/rust/crates/kernlog".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/external/rust/crates/kernlog";
    rev = "18acd4fc9e7ee4171353b297103c6f9ffe273b42";
    sha256 = "1pr4r0yrxqknbwsyc2ysvgw0f8y9hpl78ibgb2kgl84jkfiknycp";
  };
  source.dirs."external/rust/crates/command-fds".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/external/rust/crates/command-fds";
    rev = "bd13c06228d65bfca078eacb24359c5af4b1c315";
    sha256 = "1m3wzz4jpbf1s72d3281i9xnmblngwfp6gavzcfmxpv4nl42a024";
  };
  source.dirs."external/exfatprogs".src = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/external/exfatprogs";
    rev = "8a23710bb203f1920b80550969209822a849b845";
    sha256 = "1v991q9vyjivkp62svlyxbg8d8hyyfg66jvdamcjd59mjm3jxrgv";
  };
})
