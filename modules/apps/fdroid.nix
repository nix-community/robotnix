# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  apks,
  lib,
  robotnixlib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

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

    fingerprint = mkOption {
      type = types.strMatching "[0-9A-F]{64}";
      apply = lib.toUpper;
      description = ''
        The certificate fingerprint of the F-Droid APK. This is required
        because the F-Droid privileged extension checks the signature of the
        F-Droid APK to prevent unauthorized access.
      '';
    };

    # See also `apps/src/main/java/org/fdroid/fdroid/data/DBHelper.java` in F-Droid source
    additionalRepos = mkOption {
      default = { };
      description = ''
        Additional F-Droid repositories to include in the default build.
        Note that changes to this setting will only take effect on a freshly
        installed device--or if the F-Droid storage is cleared.
      '';
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
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
                type = types.enum [
                  "ignore"
                  "prompt"
                  "always"
                ];
                description = "Allow this repository to specify apps which should be automatically installed/uninstalled";
                default = "ignore";
              };

              pubkey = mkOption {
                # Wew these are long AF. TODO: Some way to generate these?
                type = types.str;
                description = "Public key associated with this repository. Can be found in `/index.xml` under the repo URL.";
              };
            };
          }
        )
      );
    };
  };

  config = mkIf cfg.enable {
    apps.fdroid.fingerprint = lib.mkIf (
      config.apps.prebuilt."F-Droid".certificate == "PRESIGNED"
    ) "43238D512C1E5EB2D6569F4A3AFBF5523418B82E0A3ED1552770ABB9A9C9CCAB";

    apps.prebuilt."F-Droid" = {
      apk = pkgs.fetchurl {
        urls =
          let
            version = "1023051";
          in
          [
            "https://f-droid.org/repo/org.fdroid.fdroid_${version}.apk"
            "https://f-droid.org/archive/org.fdroid.fdroid_${version}.apk"
          ];
        sha256 = "sha256-HfzkJpCBaT8QNQ26vSaZGlnXwruB+HDeVOWxE/R4W3o=";
      };

      certificate = "PRESIGNED";
      usesOptionalLibraries = [
        "androidx.window.extensions"
        "androidx.window.sidecar"
      ];
    };

    # TODO: Put this under product/
    source.dirs."robotnix/apps/F-DroidPrivilegedExtension" = {
      src = privext;
      patches = [
        (pkgs.replaceVars ./fdroid-privext.patch {
          fingerprint = lib.toLower cfg.fingerprint;
        })
      ];
    };

    system.additionalProductPackages = [ "F-DroidPrivilegedExtension" ];

    etc = mkIf (cfg.additionalRepos != { }) {
      "org.fdroid.fdroid/additional_repos.xml" = {
        partition = "system"; # TODO: Make this work in /product partition
        text = robotnixlib.configXML {
          # Their XML schema is just a list of strings. Each 7 entries represents one repo.
          additional_repos = lib.flatten (
            lib.mapAttrsToList (
              _: repo:
              with repo;
              (map (v: toString v) [
                name
                url
                description
                version
                (if enable then "1" else "0")
                pushRequests
                pubkey
              ])
            ) cfg.additionalRepos
          );
        };
      };
    };
  };
}
