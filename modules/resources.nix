{ config, pkgs, lib, robotnixlib, ... }:

# https://developer.android.com/guide/topics/resources/providing-resources
# https://developer.android.com/guide/topics/resources/more-resources.html
with lib;
let
  # TODO: Unify with robotnixlib.configXML (just need something nice for resourceTypeOverrides)
  configXML = relativePath: packageResources: ''
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
      ${concatStringsSep "\n" (mapAttrsToList
        (name: value: robotnixlib.resourceXML name value (config.resourceTypeOverrides.${relativePath}.${name} or robotnixlib.resourceType value))
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
    # TODO: Should some of these be in system?
    product.extraConfig = "PRODUCT_PACKAGE_OVERLAYS += robotnix/overlay";

    source.dirs."robotnix/overlay".src = (pkgs.symlinkJoin {
      name = "robotnix-overlay";
      paths = mapAttrsToList (relativePath: packageResources: (pkgs.writeTextFile {
        name = "${replaceStrings ["/"] ["="] relativePath}-resources";
        text = configXML relativePath packageResources;
        destination = "/${relativePath}/res/values/default.xml"; # I think it's ok that the name doesn't match the original--since they all get merged anyway
      })) config.resources;
    });
  };
}
