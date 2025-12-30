# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{
  pkgs ? import ./pkgs { },
}:

# Easier entrypoint to build android components individually
# The components.json list is just used as a convenient list of components.
# To see all components and what they install, refer to module-info.json (build with config.build.moduleInfo)

let
  lib = pkgs.lib;
  robotnixBuild = import ./default.nix {
    configuration = {
      device = "arm64";
      flavor = "vanilla";
    };
  };

  # Created using jq 'with_entries(select(.value.installed | length > 0)) | keys' module-info.json
  componentNames = lib.importJSON ./components.json;
in
lib.genAttrs componentNames (name: robotnixBuild.config.build.mkAndroidComponent name)
