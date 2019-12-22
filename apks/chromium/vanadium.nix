{ chromiumBase, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "QQ1A.191205.011.2019.12.02.23";
    sha256 = "0vidh8gi3qyi1yl1i4pb52xkqmchvz9y9k9w02jmblwfs8bhcz8k";
  };
in (chromiumBase.override {
  version = "78.0.3904.108";
  versionCode = "390410800";
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
  postPatch = attrs.postPatch + ''
    ( cd src
      for patchfile in ${vanadium_src}/*.patch; do
        ${git}/bin/git apply --unsafe-paths $patchfile
      done
    )
  '';
})
