{ config, pkgs, lib, ... }:

# https://developer.android.com/guide/topics/resources/providing-resources
# https://developer.android.com/guide/topics/resources/more-resources.html
with lib;
let
  # Guess resource type. Should normally work fine, but can't detect color/dimension types
  resourceType = r:
    if isBool r then "bool"
    else if isInt r then "integer"
    else if isString r then "string"
    else if isList r then
      (assert (length r != 0); # Cannot autodetect type of empty list
       if isInt (head r) then "integer-array"
       else if isString (head r) then "string-array"
       else assert false; "Unknown type"
      )
    else assert false; "Unknown type";
  resourceValueXML = value: type: {
    bool = if value then "true" else "false";
    color = value; # define our own specialized type for these?
    dimension = value;
    integer = toString value;
    string = value;
    integer-array = concatMapStringsSep "" (i: "<item>${toString i}</item>") value;
    string-array = concatMapStringsSep "" (i: "<item>${i}</item>") value;
    # Ignoring other typed arrays for now
  }.${type};
  resourceXML = name: value: type: ''<${type} name="${name}">${resourceValueXML value type}</${type}>'';
  configXML = relativePath: packageResources: ''
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
      ${concatStringsSep "\n" (mapAttrsToList
        (name: value: resourceXML name value (config.resourceTypeOverrides.${relativePath}.${name} or resourceType value))
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

  config.source = {
    postPatch = ''
      echo PRODUCT_PACKAGE_OVERLAYS += nixdroid/overlay >> build/make/target/product/core.mk
    '';

    dirs."nixdroid/overlay".contents = (pkgs.symlinkJoin {
      name = "nixdroid-overlay";
      paths = mapAttrsToList (relativePath: packageResources: (pkgs.writeTextFile {
        name = "${replaceStrings ["/"] ["="] relativePath}-resources";
        text = configXML relativePath packageResources;
        destination = "/${relativePath}/res/values/default.xml"; # I think it's ok that the name doesn't match the original--since they all get merged anyway
      })) config.resources;
    });
  };
}
