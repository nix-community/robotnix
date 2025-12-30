# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ lib, fetchpatch }:

{
  domain,
  repo,
  changeNumber,
  patchset ? 1,
  ...
}@args:

(fetchpatch (
  {
    name = "${
      lib.replaceStrings [ "/" ] [ "_" ] repo
    }-${builtins.toString changeNumber}-${builtins.toString patchset}.patch";
    url = "https://${domain}/changes/${
      lib.replaceStrings [ "/" ] [ "%2F" ] repo
    }~${builtins.toString changeNumber}/revisions/${builtins.toString patchset}/patch?download";
  }
  // builtins.removeAttrs args [
    "domain"
    "repo"
    "changeNumber"
    "patchset"
  ]
)).overrideAttrs
  (
    { postFetch, ... }:
    {
      postFetch =
        ''
          base64 -d <$out >${builtins.toString changeNumber}.patch
          mv ${builtins.toString changeNumber}.patch $out
        ''
        + postFetch;
    }
  )
