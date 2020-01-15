{ chromiumBase, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "QQ1A.200105.002.2020.01.06.21";
    sha256 = "18r5b8m2ls4c6v5fpalrf6ykhxzcshq1xndjpn1z3m8jayg27dmz";
  };
in (chromiumBase.override {
  version = "79.0.3945.93";
  versionCode = "394509300";
  customGnFlags = {
    is_component_build = false;
    is_debug = false;
    is_official_build = true;
    symbol_level = 1;
    fieldtrial_testing_like_official_build = true;

    # enable patented codecs
    ffmpeg_branding = "Chrome";
    proprietary_codecs = true;

    is_cfi = true;

    enable_remoting = false;
    enable_reporting = false;
  };
}).overrideAttrs (attrs: {
  # Use git apply below since some of these patches use "git binary diff" format
  postPatch = ''
    ( cd src
      for patchfile in ${vanadium_src}/*.patch; do
        ${git}/bin/git apply --unsafe-paths $patchfile
      done
    )
  '' + attrs.postPatch;
})
