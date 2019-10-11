{ config, pkgs, lib, nixdroidlib, ... }:

with lib;
let
  cfg = config.apps.fdroid;
  privext = pkgs.fetchFromGitLab {
    owner = "fdroid";
    repo = "privileged-extension";
    rev = "0.2.9";
    sha256 = "0r2s7zyrkfhl88sal8jifhnq47s5p7bs340ifrm9pi7vq91ydvil";
  };
in
{
  options.apps.fdroid = {
    enable = mkEnableOption "F-Droid";

    # See apps/src/main/java/org/fdroid/fdroid/data/DBHelper.java in fdroid source
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
    apps.prebuilt."F-Droid".apk = pkgs.callPackage ./fdroid {};

    # TODO: Put this under product/
    source.dirs."nixdroid/apps/F-DroidPrivilegedExtension" = {
      contents = privext;
      patches = [
        (pkgs.substituteAll {
          src = ./fdroid/privext.patch;
          fingerprint = toLower (config.build.fingerprints "releasekey");
        })
      ];
    };

    system.additionalProductPackages = [ "F-DroidPrivilegedExtension" ];

    etc = mkIf (cfg.additionalRepos != {}) {
      "org.fdroid.fdroid/additional_repos.xml".text = nixdroidlib.configXML {
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
}
