# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ chromium, fetchFromGitHub, git }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "SQ1A.211205.008.2021121602";
    sha256 = "1vqsfj73l6fmvq5i3j9ckxaphnc6h31zxglp9fn6kmard9f4fa1k";
  };
in (chromium.override {
  name = "vanadium";
  displayName = "Vanadium";
  version = "96.0.4664.104";
  enableRebranding = false; # Patches already include rebranding
  customGnFlags = {
    is_component_build = false;
    is_debug = false;
    is_official_build = true;
    symbol_level = 1;
    disable_fieldtrial_testing_config = true;

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
