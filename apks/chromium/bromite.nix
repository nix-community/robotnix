{ chromiumBase, fetchFromGitHub }:

let
  version = "79.0.3945.107";

  bromite_src = fetchFromGitHub {
    owner = "bromite";
    repo = "bromite";
    rev = version;
    sha256 = "10i7608vn9g21119il8jca9cpwz42fac4kx79sabryqd2shzcswc";
  };

in (chromiumBase.override {
  inherit version;
  versionCode = "394510700"; # TODO: Calculate
  customGnFlags = { # From bromite/build/GN_ARGS
    blink_symbol_level=1;
    dcheck_always_on=false;
    debuggable_apks=false;
    dfmify_dev_ui=false;
    disable_android_lint=true;
    disable_autofill_assistant_dfm=true;
    disable_tab_ui_dfm=true;
    enable_av1_decoder=true;
    enable_dav1d_decoder=true;
    enable_feed_in_chrome=false;
    enable_gvr_services=false;
    enable_hangout_services_extension=false;
    enable_iterator_debugging=false;
    enable_mdns=false;
    enable_mse_mpeg2ts_stream_parser=true;
    enable_nacl=false;
    enable_nacl_nonsfi=false;
    enable_remoting=false;
    enable_reporting=false;
    enable_resource_whitelist_generation=false;
    enable_vr=false;
    fieldtrial_testing_like_official_build=true;
    icu_use_data_file=true;
    is_cfi=true;
    is_component_build=false;
    is_debug=false;
    is_official_build=true;
    rtc_build_examples=false;
    safe_browsing_mode=0;
    strip_absolute_paths_from_debug_symbols=true;
    symbol_level=1;
    use_debug_fission=true;
    use_errorprone_java_compiler=false;
    use_official_google_api_keys=false;
    use_openh264=true;
    chrome_pgo_phase=0;
    full_wpo_on_official=true;
    use_sysroot=false;
  };
}).overrideAttrs (attrs: {
  postPatch = attrs.postPatch + ''
    ( cd src
      cat ${bromite_src}/build/bromite_patches_list.txt | while read patchfile; do
        patch -p1 < ${bromite_src}/build/patches/$patchfile
      done
    )
  '';
})
