{ chromiumBase, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "QQ2A.200305.002.2020.03.03.03";
    sha256 = "19dvb7lpfqv7gpwskqbfssp1jfzv46k5qsqh4pi229ypa2c4bfqj";
  };
in (chromiumBase.override {
  version = "80.0.3987.119";
  versionCode = "398711900";
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
