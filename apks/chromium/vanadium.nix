# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ chromium, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "RQ3A.210705.001.2021.07.19.18";
    sha256 = "15jq9s6jbf7ym3z8iml4z0d6xpx6c0by6vc4w31j0vs2qkplns18";
  };
in (chromium.override {
  name = "vanadium";
  displayName = "Vanadium";
  version = "91.0.4472.164";
  enableRebranding = false; # Patches already include rebranding
  customGnFlags = {
    is_component_build = false;
    is_debug = false;
    is_official_build = true;
    symbol_level = 1;
    fieldtrial_testing_like_official_build = true;

    dfmify_dev_ui = false;
    disable_autofill_assistant_dfm = true;
    disable_tab_ui_dfm = true;

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
