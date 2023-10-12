# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ chromium, fetchFromGitHub, git, fetchcipd, linkFarmFromDrvs, fetchurl, lib }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "113.0.5672.62.1";
    sha256 = "sha256-++9Pt/5jzqcf1E3FteIXkMbd+Nw0xfeDlNVAkj58Ve8=";
  };
in
(chromium.override rec {
  name = "vanadium";
  displayName = "Vanadium";
  version = "113.0.5672.62";
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
    use_cfi_cast = true;
    use_relative_vtables_abi = false;

    enable_gvr_services = false;
    enable_remoting = false;
    enable_reporting = true; # 83.0.4103.83 build is broken without building this code
  };
  # Needed for patces/0082-update-dependencies.patch in earlier versions of vanadium
  # -- this patch no longer exists at least as of 112.
  depsOverrides =
    if (version < "112") then {
      "src/third_party/android_deps/libs/com_google_android_gms_play_services_base" = linkFarmFromDrvs "play-services-base" [
        (fetchurl {
          name = "play-services-base-18.0.1.aar";
          url = "https://maven.google.com/com/google/android/gms/play-services-base/18.0.1/play-services-base-18.0.1.aar";
          sha256 = "1pl3is31asnvz26d417wxw532p72mm2wxfav55kj3r9b8dpxg5i8";
        })
      ];
      "src/third_party/android_deps/libs/com_google_android_gms_play_services_basement" = linkFarmFromDrvs "play-services-basement" [
        (fetchurl {
          name = "play-services-basement-18.0.0.aar";
          url = "https://maven.google.com/com/google/android/gms/play-services-basement/18.0.0/play-services-basement-18.0.0.aar";
          sha256 = "1mlxkysargkd8samkzfxbyilla3n9563hlijkwwjs6lhcxs7gham";
        })
      ];
      "src/third_party/android_deps/libs/com_google_android_gms_play_services_tasks" = linkFarmFromDrvs "play-services-tasks" [
        (fetchurl {
          name = "play-services-tasks-18.0.1.aar";
          url = "https://maven.google.com/com/google/android/gms/play-services-tasks/18.0.1/play-services-tasks-18.0.1.aar";
          sha256 = "108nxfl87hm8rg6pvymkbqszfbyhxi5c9bd72l9qxyncqr4dn1pi";
        })
      ];
    } else { };
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
