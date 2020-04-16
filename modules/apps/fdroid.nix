{ config, pkgs, apks, lib, robotnixlib, ... }:

with lib;
let
  cfg = config.apps.fdroid;
  privext = pkgs.fetchFromGitLab {
    owner = "fdroid";
    repo = "privileged-extension";
    rev = "0.2.11";
    sha256 = "1famqm8l15a0g5l8h4b0x4km9iq98v8nl1qf2rbhps274n307rmq";
  };
in
{
  options.apps.fdroid = {
    enable = mkEnableOption "F-Droid";

    # See apps/src/main/java/org/fdroid/fdroid/data/DBHelper.java in fdroid source
    # Note that changes to this setting will only take effect on a freshly
    # installed device--or if the FDroid storage is cleared
    additionalRepos = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkEnableOption name;

          name = mkOption {
            default = name;
            type = types.str;
          };

          url = mkOption {
            type = types.str;
          };

          description = mkOption {
            default = "Empty description"; # fdroid parsing of additional_repos.xml requires all items to have text
            type = types.str;
          };

          version = mkOption { # Not sure what this one is for exactly
            default = 1;
            type = types.int;
          };

          pushRequests = mkOption { # Repo metadata can specify apps to be installed/removed
            type = types.strMatching "(ignore|prompt|always)";
            default = "ignore";
          };

          pubkey = mkOption { # Wew these are long AF. TODO: Some way to generate these?
            type = types.str;
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    apps.prebuilt."F-Droid".apk = apks.fdroid;

    # TODO: Put this under product/
    source.dirs."robotnix/apps/F-DroidPrivilegedExtension" = {
      src = privext;
      patches = [
        (pkgs.substituteAll {
          src = ./fdroid-privext.patch;
          fingerprint = toLower (config.build.fingerprints "releasekey");
        })
      ];
    };

    system.additionalProductPackages = [ "F-DroidPrivilegedExtension" ];

    etc = mkIf (cfg.additionalRepos != {}) {
      "org.fdroid.fdroid/additional_repos.xml" = {
        partition = "system"; # TODO: Make this work in /product partition
        text = robotnixlib.configXML {
          # Their XML schema is just a list of strings. Each 7 entries represents one repo.
          additional_repos = flatten (mapAttrsToList (_: repo: with repo; (map (v: toString v) [
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
