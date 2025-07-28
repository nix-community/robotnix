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
    yarnHash = lib.mkOption {
      type = lib.types.str;
    };
    img = lib.mkOption {
      type = lib.types.str;
    };
    ota = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    envPackages = with pkgs; [ nodejs yarn ];
    source = {
      overlayfsDirs = [ "vendor/adevtool" ];
      dirs."vendor/adevtool" = {
        nativeBuildInputs = with pkgs; [ nodejs yarnConfigHook ];
        postPatch = let
          yarnOfflineCache = pkgs.fetchYarnDeps {
            yarnLock = config.source.dirs."vendor/adevtool".manifestSrc + "/yarn.lock";
            sha256 = cfg.yarnHash;
          };
        in ''
          yarnOfflineCache=${yarnOfflineCache}
          yarnConfigHook
        '';
      };
    };
  };
}
