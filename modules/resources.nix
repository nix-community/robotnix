{ config, pkgs, lib, nixdroidlib, ... }:

# https://developer.android.com/guide/topics/resources/providing-resources
# https://developer.android.com/guide/topics/resources/more-resources.html
with lib;
let
  # TODO: Unify with nixdroidlib.configXML (just need something nice for resourceTypeOverrides)
  configXML = relativePath: packageResources: ''
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
      ${concatStringsSep "\n" (mapAttrsToList
        (name: value: nixdroidlib.resourceXML name value (config.resourceTypeOverrides.${relativePath}.${name} or nixdroidlib.resourceType value))
       packageResources)}
    </resources>
  '';
in
{
  options = {
    resources = mkOption {
      default = {};
      type = types.attrsOf (types.attrsOf types.unspecified);
      description = "package resources. The first key refers to the relative path for the package, and the second key refers to the resource name";
    };

    resourceTypeOverrides = mkOption {
      default = {};
      type = types.attrsOf (types.attrsOf (types.strMatching "(bool|integer|dimen|color|string|integer-array|string-array)"));
      description = "for overriding auto-detected resource type";
    };
  };

  config = {
    extraConfig = "PRODUCT_PACKAGE_OVERLAYS += nixdroid/overlay";

    source.dirs."nixdroid/overlay".contents = (pkgs.symlinkJoin {
      name = "nixdroid-overlay";
      paths = mapAttrsToList (relativePath: packageResources: (pkgs.writeTextFile {
        name = "${replaceStrings ["/"] ["="] relativePath}-resources";
        text = configXML relativePath packageResources;
        destination = "/${relativePath}/res/values/default.xml"; # I think it's ok that the name doesn't match the original--since they all get merged anyway
      })) config.resources;
    });
  };
}
