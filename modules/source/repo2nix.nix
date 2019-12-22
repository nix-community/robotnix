{
 pkgs ? import ../../pkgs.nix {},
 manifest, rev, sha256
# Optional parameters:
, repoRepoURL ? "https://github.com/danielfullmer/tools_repo"
, repoRepoRev ? "master"
, referenceDir ? ""
, extraFlags ? "--no-repo-verify"
, localManifests ? []
, withTreeHashes ? false
}:
# withTreeHashes enables additionally fetching the git SHA1 hash of the actual
# tree associated with the tag/commit.  This is valuable since android sources
# have many tags/commits across devices pointing to the same tree--but with
# different commit messages.  This allows us to deduplicate these sources which
# have the same sha256 hash, without having to fetch them all individually.
# Since there is no clear way to have git fetch these tree hashes directly
# without fetching too much information, we rely on the web interface at
# android.googlesource.com

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

  nativeBuildInputs = [ gitRepo cacert ] ++ (optionals withTreeHashes [ curl jq go-pup ]);

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
  '' + (optionalString withTreeHashes "bash ${./fetch-treehashes.sh} $out");
}
