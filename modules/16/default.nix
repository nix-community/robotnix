# SPDX-FileCopyrightText: 2025 cyclopentane and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
lib.mkIf (config.androidVersion == 16) {
  source.dirs = {
    "system/core".patches = [
      ./platform_system_core_permissions.patch
    ];

    "build/make".patches = [
      ./0001-Readonly-source-fix.patch
    ];

    "external/avb".patches = [
      ./avbtool-set-perms.patch
    ];
  };
}
