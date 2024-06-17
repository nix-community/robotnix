# SPDX-FileCopyrightText: 2022 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkIf mkOption types;
in
{
  options = {
    security.pki.certificateFiles = mkOption {
      default = [ ];
      type = types.listOf types.path;
      description = "A list of files containing trusted root certificates in PEM format.  These are added as system-level trust anchors.";
    };
  };

  config = mkIf (config.security.pki.certificateFiles != [ ]) {
    source.dirs."system/ca-certificates".postPatch = lib.concatMapStringsSep "\n" (certFile: ''
      cp -v ${lib.escapeShellArg "${certFile}"} $out/files/$(${pkgs.openssl}/bin/openssl x509 -inform PEM -subject_hash_old -in ${lib.escapeShellArg "${certFile}"} -noout).0
    '') config.security.pki.certificateFiles;
  };
}
