{ chromiumBase, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "QQ2A.200305.002.2020.03.04.16";
    sha256 = "023w055v8v0z7f53bncx6f7m3dlygwah6247y7ijpvg198cif5rm";
  };
in (chromiumBase.override {
  version = "80.0.3987.132";
  versionCode = "398713200";
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
