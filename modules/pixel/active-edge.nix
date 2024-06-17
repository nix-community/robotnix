{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    assertMsg
    mkIf
    mkEnableOption
    mkMerge
    mkOption
    types
    ;

  cfg = config.pixel.activeEdge;
in

{
  options = {
    pixel.activeEdge = {
      enable = mkEnableOption "Active Edge gestures using the open-source implementation from LineageOS";
      includedInFlavor = mkOption {
        type = types.bool;
        internal = true;
        default = false;
        description = "Whether Active Edge support is already included in the chosen flavor";
      };
    };
  };

  config =
    let
      deviceSupported = builtins.elem config.device [
        "taimen"
        "walleye"
        "crosshatch"
        "blueline"
        "bonito"
        "sargo"
        "coral"
        "flame"
      ];
    in
    mkIf (cfg.enable && !cfg.includedInFlavor) (mkMerge [
      {
        assertions = [
          {
            assertion = deviceSupported;
            message = "${config.deviceDisplayName} does not include Active Edge functionality";
          }
          {
            assertion = builtins.elem config.androidVersion [
              11
              12
            ];
            message = "Active Edge support is only implemented on Android 11 and 12 in Robotnix";
          }
        ];

        product.additionalProductPackages = [ "ElmyraService" ];

        source.dirs."frameworks/base".patches = [
          # SystemUI: Allow privileged system apps to access screenshot service
          (pkgs.fetchpatch {
            name = "SystemUI-Allow-privileged-system-apps-to-access-screenshot-service.patch";
            url = "https://github.com/LineageOS/android_frameworks_base/commit/c927518f8274be804597af538f3d0e7c4da9c39a.patch";
            sha256 = "sha256-6SvTDtMemk8oN1xXc6TNIOgkXp66Ak9yfANMNX8nwuE=";
          })

          # core: Expose method to start assistant through Binder
          (pkgs.fetchpatch {
            name = "core-Expose-method-to-start-assistant-through-Binder.patch";
            url = "https://github.com/ProtonAOSP/android_frameworks_base/commit/2b950e103e865aa6a1fe8a917964e0069d4c4037.patch";
            sha256 = "sha256-hj2F9W6njqGs9SccPEfbnMak/FLqNTQpgkVJQE+l2V0=";
          })
        ];
      }

      (mkIf (config.androidVersion == 11) {
        source.dirs."packages/apps/ElmyraService".src = pkgs.fetchFromGitHub {
          owner = "LineageOS";
          repo = "android_packages_apps_ElmyraService";
          rev = "4b6befa8559d63643d3218c244b7f6287197aca2";
          sha256 = "sha256-CmEmdt5rhc+cGqCJY/REPl4eAwGjS7Z8i7NkynNjGl4=";
        };
      })

      (mkIf (config.androidVersion == 12) {
        source.dirs."packages/apps/ElmyraService".src = pkgs.fetchFromGitHub {
          owner = "LineageOS";
          repo = "android_packages_apps_ElmyraService";
          rev = "94823b39e30bd68e30f74ef518dff8ac56d70537";
          sha256 = "sha256-MwNDLbwicDasJSxJVfzoMcVYpWn7tSd7zBKQaRSvmvw=";
        };
      })
    ]);
}
