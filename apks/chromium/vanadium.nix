{ chromium, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "RP1A.201105.002.2020.11.03.03";
    sha256 = "0m0p90mx9sainrs5sgmyrapv31mlx034n411jfs9xqv8gvbj7km0";
  };
in (chromium.override {
  name = "vanadium";
  displayName = "Vanadium";
  version = "86.0.4240.185";
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
    enable_reporting = true; # 83.0.4103.83 build is broken without building this code
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
