# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, robotnixlib, ... }:

# https://developer.android.com/guide/topics/resources/providing-resources
# https://developer.android.com/guide/topics/resources/more-resources.html
with lib;
let
  # TODO:
  # "oneOf [ (listOf int) (listOf str) ]" doesn't work. Fails with str looking for int
  # Using "listOf (either str int)" instead
  resourceTypeGeneric = with types; oneOf [ bool int str (listOf (either str int)) ];
  resourceTypeModule = types.submodule ({ name, config, ... }: {
    options = {
      type = mkOption {
        type = types.strMatching "(bool|integer|dimen|color|string|integer-array|string-array)";
        description = "Set to override auto-detected resource type";
      };

      value = mkOption {
        type = resourceTypeGeneric;
      };
    };

    config = {
      type = mkOptionDefault (resourceTypeName config.value);
    };
  });
in
{
  options = {
    resources = mkOption {
      default = {};
      type = with types; attrsOf (attrsOf (either resourceTypeGeneric resourceTypeModule));
      description = "Package resources. The first key refers to the relative path for the package, and the second key refers to the resource name";
    };
  };

  config = {
    # TODO: Should some of these be in system?
    product.extraConfig = "PRODUCT_PACKAGE_OVERLAYS += robotnix/overlay";

    source.dirs."robotnix/overlay".src = (pkgs.symlinkJoin {
      name = "robotnix-overlay";
      paths = mapAttrsToList (relativePath: packageResources: (pkgs.writeTextFile {
        name = "${replaceStrings ["/"] ["="] relativePath}-resources";
        text = robotnixlib.configXML packageResources;
        destination = "/${relativePath}/res/values/default.xml"; # I think it's ok that the name doesn't match the original--since they all get merged anyway
      })) config.resources;
    });
  };
}
