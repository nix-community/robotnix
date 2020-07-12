{ lib, fetchpatch }:

{ repo, changeNumber, patchset ? 1, ...  }@args:

(fetchpatch ({
    name = "${lib.replaceStrings ["/"] ["_"] repo}-${builtins.toString changeNumber}-${builtins.toString patchset}.patch";
    url = "https://android-review.googlesource.com/changes/${lib.replaceStrings ["/"] ["%2F"] repo}~${builtins.toString changeNumber}/revisions/${builtins.toString patchset}/patch?download";
  } // builtins.removeAttrs args [ "repo" "changeNumber" "patchset" ])
).overrideAttrs ({ postFetch, ... }: {
  postFetch = ''
    base64 -d <$out >${builtins.toString changeNumber}.patch
    mv ${builtins.toString changeNumber}.patch $out
  '' + postFetch;
})
