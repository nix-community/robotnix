{ config, lib, pkgs, ... }:
let
  cfg = config.adevtool;
in {
  options.adevtool = {
    enable = lib.mkEnableOption "the adevtool module";
    buildID = lib.mkOption {
      type = lib.types.str;
      default = "The build ID as specified in `build/make/core/build_id.mk` in the AOSP source tree.";
    };
    img = lib.mkOption {
      type = lib.types.str;
    };
    ota = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    source.overlayfsDirs = [ "vendor/adevtool" ];
    envPackages = with pkgs; [ nodejs yarn ];
  };
}
