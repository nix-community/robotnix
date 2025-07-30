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
      type = lib.types.path;
    };
    imgFilename = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    envPackages = with pkgs; [
      # Needed for running adevtool.
      nodejs
      yarn

      # adevtool uses e2fsprogs `debugfs` to extract the vendor ext4 images.
      e2fsprogs
    ];
    source = {
      overlayfsDirs = [ "vendor/adevtool" ];
      dirs = {
        "vendor/adevtool" = {
          nativeBuildInputs = with pkgs; [ nodejs yarnConfigHook ];
          patches = [
            ./adevtool-ignore-EINVAL-upon-chown.patch
          ];
          postPatch = let
            yarnOfflineCache = pkgs.fetchYarnDeps {
              yarnLock = config.source.dirs."vendor/adevtool".manifestSrc + "/yarn.lock";
              sha256 = cfg.yarnHash;
            };
          in ''
            yarnOfflineCache=${yarnOfflineCache}
            yarnConfigHook
            mkdir -p dl
            ln -s ${cfg.img} dl/${cfg.imgFilename}
          '';
        };

        "vendor/google_devices" = {
          src = config.build.vendor_google_devices;
        };
      };
    };

    build.vendor_google_devices = config.build.mkAndroid {
      name = "vendor_google_devices-${config.device}";
      excludedDirs = [ "vendor/google_devices" ];
      makeTargets = [ "arsclib" ];
      postBuild = ''
        mkdir -p /tmp/vendor_imgs
        export ADEVTOOL_IMG_DOWNLOAD_DIR=/tmp/vendor_imgs
        ln -s ${cfg.img} /tmp/vendor_imgs/${cfg.imgFilename}
        vendor/adevtool/bin/run generate-all -d ${config.device}
      '';
      installPhase = ''
        cp -r vendor/google_devices $out
      '';
    };
  };
}
