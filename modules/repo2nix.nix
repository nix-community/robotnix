# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT
{
 pkgs ? import ../pkgs {},
 manifest, rev, sha256
# Optional parameters:
, repoRepoURL ? "https://github.com/danielfullmer/tools_repo"
, repoRepoRev ? "master"
, referenceDir ? ""
, extraFlags ? "--no-repo-verify"
, localManifests ? []
}:

assert repoRepoRev != "" -> repoRepoURL != "";

# stdenvNoCC, gitRepo, cacert, copyPathsToStore 
with pkgs;
with pkgs.lib;

let
  extraRepoInitFlags = [
    (optionalString (repoRepoURL != "") "--repo-url=${repoRepoURL}")
    (optionalString (repoRepoRev != "") "--repo-rev=${repoRepoRev}")
    (optionalString (referenceDir != "") "--reference=${referenceDir}")
    (optionalString (extraFlags != "") "${extraFlags}")
  ];

  repoInitFlags = [
    "--manifest-url=${manifest}"
    "--manifest-branch=${rev}"
    "--depth=1"
  ] ++ extraRepoInitFlags;
in stdenvNoCC.mkDerivation {
  name = "repo2json-${replaceStrings ["/"] ["="] rev}";

  outputHashAlgo = "sha256";
  outputHash = sha256;

  preferLocalBuild = true;
  enableParallelBuilding = true;

  impureEnvVars = fetchers.proxyImpureEnvVars ++ [
    "GIT_PROXY_COMMAND" "SOCKS_SERVER"
  ];

  nativeBuildInputs = [ git-repo cacert ];

  GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  buildCommand = ''
    # Path must be absolute (e.g. for GnuPG: ~/.repoconfig/gnupg/pubring.kbx)
    export HOME="$(pwd)"

    mkdir -p .repo/local_manifests

  '' +
    (concatMapStringsSep "\n"
    (localManifest: "cp ${localManifest} .repo/local_manifests/$(stripHash ${localManifest}; echo $strippedName)")
    localManifests)
  + ''

    # XXX: Hack since android.googlesource.com and recent curl version don't play nicely.
    ${pkgs.git}/bin/git config --global http.version HTTP/1.1

    repo init ${concatStringsSep " " repoInitFlags}
    repo dumpjson > "$out"

    rm -rf .repo*
  '';
}
