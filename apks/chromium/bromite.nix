# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT

{
  chromium,
  fetchFromGitHub,
  git,
  python3,
}:

let
  version = "100.0.4896.135";

  bromite_src = fetchFromGitHub {
    owner = "bromite";
    repo = "bromite";
    rev = version;
    sha256 = "sha256-eD+VINsuBojPi6KaGjiBnQz0k1Q1PdKPsGsJCziFdug=";
  };

in
(chromium.override {
  name = "bromite";
  displayName = "Bromite";
  inherit version;
  enableRebranding = true;
  customGnFlags = {
    # From bromite/build/GN_ARGS
    blink_symbol_level = 1;
    build_contextual_search = false;
    build_with_tflite_lib = false;
    chrome_pgo_phase = 0;
    dcheck_always_on = false;
    debuggable_apks = false;
    dfmify_dev_ui = false;
    disable_android_lint = true;
    disable_autofill_assistant_dfm = true;
    disable_fieldtrial_testing_config = true;
    disable_tab_ui_dfm = true;
    enable_av1_decoder = true;
    enable_dav1d_decoder = true;
    enable_gvr_services = false;
    enable_hangout_services_extension = false;
    enable_iterator_debugging = false;
    enable_mdns = false;
    enable_mse_mpeg2ts_stream_parser = true;
    enable_nacl = false;
    enable_platform_dolby_vision = true;
    enable_platform_hevc = true;
    enable_remoting = false;
    enable_reporting = false;
    enable_supervised_users = false;
    enable_vr = false;
    exclude_unwind_tables = false;
    ffmpeg_branding = "Chrome";
    icu_use_data_file = true;
    is_cfi = true;
    is_component_build = false;
    is_debug = false;
    is_official_build = true;
    proprietary_codecs = true;
    rtc_build_examples = false;
    safe_browsing_mode = 0;
    symbol_level = 1;
    use_cfi_cast = true;
    use_debug_fission = true;
    use_errorprone_java_compiler = false;
    use_gnome_keyring = false;
    use_official_google_api_keys = false;
    use_rtti = false;
    use_sysroot = false;
    webview_includes_weblayer = false;

    # XXX: Hack. Not sure why it's not being set correctly when building webview
    rtc_use_x11 = false;
    rtc_use_x11_extensions = false;
    rtc_use_pipewire = false;
  };
}).overrideAttrs
  (attrs: {
    postPatch =
      ''
        ( cd src
          cat ${bromite_src}/build/bromite_patches_list.txt | while read patchfile; do
            echo Applying $patchfile
            ${git}/bin/git apply --unsafe-paths "${bromite_src}/build/patches/$patchfile"
          done

          # Disable Auto updater by default. It's only set up to work with official builds.
          substituteInPlace chrome/android/java/src/org/chromium/chrome/browser/omaha/inline/BromiteInlineUpdateController.java \
            --replace "private boolean mEnabled = true" "private boolean mEnabled = false"
        )
      ''
      + attrs.postPatch;
  })
