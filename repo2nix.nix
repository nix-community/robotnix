{
 pkgs ? import ./pkgs.nix,
 manifest, rev, sha256
# Optional parameters:
, repoRepoURL ? /home/danielrf/src/tools_repo
, repoRepoRev ? "master"
, referenceDir ? ""
, extraFlags ? "--no-repo-verify"
, localManifests ? []
}:

assert repoRepoRev != "" -> repoRepoURL != "";

# stdenvNoCC, gitRepo, cacert, copyPathsToStore 
with pkgs;
with stdenvNoCC.lib;

let
  extraRepoInitFlags = [
    (optionalString (repoRepoURL != "") "--repo-url=${repoRepoURL}")
    (optionalString (repoRepoRev != "") "--repo-branch=${repoRepoRev}")
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

  nativeBuildInputs = [ gitRepo cacert ];

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

    repo init ${concatStringsSep " " repoInitFlags}
    repo dumpjson > "$out"

    rm -rf .repo*
  '';
}
