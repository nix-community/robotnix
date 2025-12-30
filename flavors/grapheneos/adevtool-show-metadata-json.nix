tag:
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  adevtoolEntry = (lib.importJSON (./. + "/${tag}/repo.lock")).entries."vendor/adevtool";
  adevtool = pkgs.fetchgit (
    with adevtoolEntry;
    {
      url = project.repo_ref.repo_url;
      rev = lock.commit;
      hash = lock.nix_hash;
    }
  );
  yarnOfflineCache = pkgs.fetchYarnDeps {
    yarnLock = "${adevtool}/yarn.lock";
    sha256 = (lib.importJSON ./yarn_hashes.json).${tag};
  };
  adevtool' =
    pkgs.runCommand "adevtool"
      {
        nativeBuildInputs = with pkgs; [
          yarnConfigHook
        ];
      }
      ''
        mkdir -p $out/vendor
        cp -r ${adevtool} $out/vendor/adevtool
        chmod -R u+w $out
        cd $out/vendor/adevtool
        patch -p1 < ${
          if lib.versionAtLeast tag "2025111800" then
            ./adevtool-show-metadata-json-after-2025111800.patch
          else
            ./adevtool-show-metadata-json.patch
        }
        yarnOfflineCache=${yarnOfflineCache}
        yarnConfigHook
      '';
in
adevtool'
