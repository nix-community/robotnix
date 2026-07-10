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

  # In https://android.googlesource.com/platform/build/+/322b51b245bc70bcbbd5538d40dd47c45565b67f,
  # AOSP switched over to using Soong for otatools.zip.
  otatoolsOutPath = "$ANDROID_HOST_OUT/obj/ETC/otatools-package*_intermediates/otatools-package*";

}
