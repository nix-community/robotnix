{ config, pkgs, lib, ... }:

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
  options = {
    apps.fdroid.enable = mkEnableOption "F-Droid";
  };

  config = mkIf cfg.enable {
    apps.prebuilt."F-Droid".apk = pkgs.callPackage ./fdroid {};

    source.dirs."nixdroid/apps/F-DroidPrivilegedExtension".contents = pkgs.runCommand "froid-privext-patched" {} ''
      mkdir -p $out
      cp -r ${privext}/* $out
      chmod u+w -R $out

      cd $out
      patch -p1 < ${./fdroid/privext.patch}
      substituteInPlace app/src/main/java/org/fdroid/fdroid/privileged/ClientWhitelist.java \
       --replace 43238d512c1e5eb2d6569f4a3afbf5523418b82e0a3ed1552770abb9a9c9ccab "${config.build.fingerprints "platform"}"
    '';

    additionalProductPackages = [ "F-DroidPrivilegedExtension" ];
  };
}
