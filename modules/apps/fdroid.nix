# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, apks, lib, robotnixlib, ... }:

let
  inherit (lib) mkIf mkOption mkEnableOption types;

  cfg = config.apps.fdroid;
  privext = pkgs.fetchFromGitLab {
    owner = "fdroid";
    repo = "privileged-extension";
    rev = "0.2.13";
    sha256 = "sha256-lS/U42uBpfT0M8mlqGklG8tYB5qMrMnLK4+V89yFcH0=";
  };
in
{
  options.apps.fdroid = {
    enable = mkEnableOption "F-Droid";

    # See also `apps/src/main/java/org/fdroid/fdroid/data/DBHelper.java` in F-Droid source
    additionalRepos = mkOption {
      default = {};
      description = ''
        Additional F-Droid repositories to include in the default build.
        Note that changes to this setting will only take effect on a freshly
        installed device--or if the F-Droid storage is cleared.
      '';
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkOption {
            default = false;
            type = types.bool;
            description = "Whether to enable this repository by default in F-Droid.";
          };

          name = mkOption {
            default = name;
            type = types.str;
            description = "Display name to use for this repository";
          };

          url = mkOption {
            type = types.str;
            description = "URL for F-Droid repository";
          };

          description = mkOption {
            type = types.str;
            default = "Empty description"; # fdroid parsing of additional_repos.xml requires all items to have text
            description = "Longer textual description of this repository";
          };

          version = mkOption {
            type = types.int;
            default = 0;
            description = "Which version of fdroidserver built this repo";
            internal = true;
          };

          pushRequests = mkOption {
            type = types.enum [ "ignore" "prompt" "always" ];
            description = "Allow this repository to specify apps which should be automatically installed/uninstalled";
            default = "ignore";
          };

          pubkey = mkOption { # Wew these are long AF. TODO: Some way to generate these?
            type = types.str;
            description = "Public key associated with this repository. Can be found in `/index.xml` under the repo URL.";
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    apps.prebuilt."F-Droid" = {
      apk = pkgs.fetchurl {
        url = "https://f-droid.org/repo/org.fdroid.fdroid_1020050.apk";
        sha256 = "sha256-wWd/so9s/Ahdp6WtFbp1sjfNlbt4pnmqqNsMGt1o8QQ=";
      };

      fingerprint = mkIf (!config.signing.enable) "7352DAE94B237866E7FB44FD94ADE44E8B6E05397E7D1FB45616A00E225063FF";
      usesOptionalLibraries = [ "androidx.window.extensions" "androidx.window.sidecar" ];
    };

    # TODO: Put this under product/
    source.dirs."robotnix/apps/F-DroidPrivilegedExtension" = {
      src = privext;
      patches = [
        (pkgs.substituteAll {
          src = ./fdroid-privext.patch;
          fingerprint = lib.toLower config.apps.prebuilt."F-Droid".fingerprint;
        })
      ];
    };

    system.additionalProductPackages = [ "F-DroidPrivilegedExtension" ];

    etc = mkIf (cfg.additionalRepos != {}) {
      "org.fdroid.fdroid/additional_repos.xml" = {
        partition = "system"; # TODO: Make this work in /product partition
        text = robotnixlib.configXML {
          # Their XML schema is just a list of strings. Each 7 entries represents one repo.
          additional_repos = lib.flatten (lib.mapAttrsToList (_: repo: with repo; (map (v: toString v) [
            name
            url
            description
            version
            (if enable then "1" else "0")
            pushRequests
            pubkey
          ])) cfg.additionalRepos);
        };
      };
    };
  };
}
