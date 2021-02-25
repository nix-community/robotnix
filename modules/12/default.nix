# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

with lib;

mkIf (config.androidVersion == 12) {
  apiLevel = 31;

  #kernel.clangVersion = mkDefault "r370808";
}
