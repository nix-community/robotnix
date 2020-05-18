{ chromium, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "QQ2A.200501.001.B3.2020.05.05.02";
    sha256 = "1xvlr83y79i0vwdjfjvgqkzi1j2r8rpgnpp7jm7sh8hy26rwhkxz";
  };
in (chromium.override {
  name = "vanadium";
  displayName = "Vanadium";
  version = "81.0.4044.117";
  enableRebranding = false; # Patches already include rebranding
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

    enable_gvr_services = false;
    enable_remoting = false;
    enable_reporting = false;
  };
}).overrideAttrs (attrs: {
  # Use git apply below since some of these patches use "git binary diff" format
  postPatch = ''
    ( cd src
      for patchfile in ${vanadium_src}/patches/*.patch; do
        ${git}/bin/git apply --unsafe-paths $patchfile
      done
    )
  '' + attrs.postPatch;
})
