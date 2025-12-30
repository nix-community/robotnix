# SPDX-FileCopyrightText: 2020 cyclopentane and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.bootanimation;
in
{
  options.bootanimation = {
    enable = lib.mkEnableOption "the custom bootanimation module";
    logoMask = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = ''
        The file to put at `frameworks/base/core/res/assets/images/android-logo-mask.png`.
      '';
    };
    logoShine = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = ''
        The file to put at `frameworks/base/core/res/assets/images/android-logo-shine.png`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    source.dirs."frameworks/base".postPatch = ''
      ${lib.optionalString (cfg.logoMask != null) ''
        cp ${cfg.logoMask} core/res/assets/images/android-logo-mask.png
      ''}
      ${lib.optionalString (cfg.logoShine != null) ''
        cp ${cfg.logoShine} core/res/assets/images/android-logo-shine.png
      ''}
    '';
  };
}
