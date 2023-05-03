# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, robotnixlib, ... }:

# https://developer.android.com/guide/topics/resources/providing-resources
# https://developer.android.com/guide/topics/resources/more-resources.html
let
  inherit (lib) mkOption mkOptionDefault types;

  # TODO:
  # "oneOf [ (listOf int) (listOf str) ]" doesn't work. Fails with str looking for int
  # Using "listOf (either str int)" instead
  resourceTypeGeneric = with types; oneOf [ bool int str (listOf (either str int)) ];
  resourceTypeModule = types.submodule ({ name, config, ... }: {
    options = {
      type = mkOption {
        type = types.enum [ "bool" "integer" "dimen" "color" "string" "integer-array" "string-array" ];
        description = "Set to override auto-detected resource type";
      };

      value = mkOption {
        type = resourceTypeGeneric;
      };
    };

    config = {
      type = mkOptionDefault (robotnixlib.resourceTypeName config.value);
    };
  });
in
{
  options = {
    resources = mkOption {
      default = { };
      type = with types; attrsOf (either
        (attrsOf (attrsOf (either resourceTypeGeneric resourceTypeModule)))
        (attrsOf (either resourceTypeGeneric resourceTypeModule))); # included for backwards-compatibility; if a key includes a "/", it's processed as a file path. if none of your keys include a "/", the default value of "values/default.xml" is used as the file path, so if you need them to be interpreted as a filepath, include a leading "/" in at least 1 attr name.
      description = "Additional package resources to include. The first key refers to the relative path for the package. The second key is the file to place the resources in; if it's not set, values/default.xml is used. The third key is the resource key to set with the provided value.";
      example = lib.literalExample ''{
        "frameworks/base/core/res"."values/config.xml".config_enableAutoPowerModes = true;
      }'';
    };
  };

  config = {
    product.extraConfig = "PRODUCT_PACKAGE_OVERLAYS += robotnix/overlay";

    source.dirs."robotnix/overlay".src = (pkgs.symlinkJoin {
      name = "robotnix-overlay";
      paths = lib.flatten (lib.mapAttrsToList
        (relativePath: packageResources:
          if lib.any (name: (lib.length (lib.splitString "/" name)) > 1) (lib.attrNames packageResources)
          then
            (lib.mapAttrsToList
              (filePath: resources: pkgs.writeTextFile {
                name = "${lib.replaceStrings ["/"] ["="] relativePath}-resources";
                text = robotnixlib.configXML resources;
                destination = "/${relativePath}/res/${filePath}";
              })
              packageResources)
          else [
            (pkgs.writeTextFile {
              name = "${lib.replaceStrings ["/"] ["="] relativePath}-resources";
              text = robotnixlib.configXML packageResources;
              destination = "/${relativePath}/res/values/default.xml";
            })
          ])
        config.resources);
    });
  };
}
