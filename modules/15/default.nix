# SPDX-FileCopyrightText: 2024 Atemu and robotnix contributors
# SPDX-License-Identifier: MIT
{ config, lib, ... }:

lib.mkIf (config.androidVersion == 15) {
  source.dirs."system/core".patches = [
    ./core-readonly.patch
  ];
  source.dirs."build/make".patches = [
    ./0001-Readonly-source-fix.patch
  ];
}
