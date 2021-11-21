# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ pkgs, callPackage, stdenv, stdenvNoCC, lib, fetchgit, fetchurl, fetchcipd, runCommand, symlinkJoin, writeScript, buildFHSUserEnv, autoPatchelfHook, buildPackages
, python2, python3, ninja, llvmPackages_11, nodejs, jre8, bison, gperf, pkg-config, protobuf, bsdiff
, dbus, systemd, glibc, at-spi2-atk, atk, at-spi2-core, nspr, nss, pciutils, utillinux, kerberos, gdk-pixbuf
, glib, gtk3, alsaLib, pulseaudio, xdg_utils, libXScrnSaver, libXcursor, libXtst, libXdamage
, libdrm, libxkbcommon
, zlib, ncurses5, libxml2, binutils, perl
, substituteAll, fetchgerritpatchset

, name ? "chromium"
, displayName ? "Chromium"
, enableRebranding ? false
, customGnFlags ? {}
, targetCPU ? "arm64"
, buildTargets ? [ "chrome_modern_public_bundle" ]
, packageName ? "org.chromium.chrome"
, webviewPackageName ? "com.android.webview"
, trichromeLibraryPackageName ? "org.chromium.trichromelibrary"
, version ? "96.0.4664.45"
, versionCode ? null
# Potential buildTargets:
# chrome_modern_public_bundle + system_webview_apk
# trichrome_webview_apk + trichrome_chrome_bundle + trichome_library_apk
# monochrome_public_apk
}:

let
  _versionCode = let
    minor = lib.fixedWidthString 4 "0" (builtins.elemAt (builtins.splitVersion version) 2);
    patch = lib.fixedWidthString 3 "0" (builtins.elemAt (builtins.splitVersion version) 3);
  in if (versionCode != null) then versionCode else "${minor}${patch}00";

  buildenv = import ./buildenv.nix { inherit pkgs; };

  # Serialize Nix types into GN types according to this document:
  # https://gn.googlesource.com/gn/+/refs/heads/master/docs/language.md
  gnToString =
    let
      mkGnString = value: "\"${lib.escape ["\"" "$" "\\"] value}\"";
      sanitize = value:
        if value == true then "true"
        else if value == false then "false"
        else if lib.isList value then "[${lib.concatMapStringsSep ", " sanitize value}]"
        else if lib.isInt value then toString value
        else if lib.isString value then mkGnString value
        else throw "Unsupported type for GN value `${value}'.";
      toFlag = key: value: "${key}=${sanitize value}";
    in
      attrs: lib.concatStringsSep " " (lib.attrValues (lib.mapAttrs toFlag attrs));

  gnFlags = {
    target_os = "android";
    target_cpu = targetCPU;

    android_channel = "stable"; # TODO: Get stable/beta/dev etc
    android_default_version_name = version;
    android_default_version_code = _versionCode;
    chrome_public_manifest_package = packageName;
    system_webview_package_name = webviewPackageName;
    trichrome_library_package = trichromeLibraryPackageName;

    is_official_build = true;
    is_debug = false;

    disable_fieldtrial_testing_config = true;

    enable_nacl = false;
    is_component_build = false;
    is_clang = true;
    clang_use_chrome_plugins = false;

    treat_warnings_as_errors = false;
    use_sysroot = false;

    use_gnome_keyring = false;
    enable_vr = false; # Currently not checking out vr stuff
    enable_remoting = false;
    enable_reporting = true; # Needs to be true for 83.* for undefined symbol error

    # enable support for the H.264 codec
    proprietary_codecs = true;
    ffmpeg_branding = "Chrome";

    # Only include minimal symbols to save space
    symbol_level = 1;
    blink_symbol_level = 1;

    # explicit host_cpu and target_cpu prevent "nix-shell pkgsi686Linux.chromium-git" from building x86_64 version
    # there is no problem with nix-build, but platform detection in nix-shell is not correct
    host_cpu   = { i686-linux = "x86"; x86_64-linux = "x64"; armv7l-linux = "arm"; aarch64-linux = "arm64"; }.${stdenv.buildPlatform.system};
    #target_cpu = { i686-linux = "x86"; x86_64-linux = "x64"; armv7l-linux = "arm"; aarch64-linux = "arm64"; }.${stdenv.hostPlatform.system};
  } // customGnFlags;

  deps = import (./vendor- + version + ".nix") { inherit fetchgit fetchcipd fetchurl runCommand symlinkJoin; };

  src = runCommand "chromium-${version}-src" {} # TODO: changed from mkDerivation since it needs passAsFile or else this can get too big for the derivation: nixos "while setting up the build environment" "argument list too long"
      # <nixpkgs/pkgs/build-support/trivial-builders.nix>'s `linkFarm` or `buildEnv` would work here if they supported nested paths
      (lib.concatStringsSep "\n" (
        lib.mapAttrsToList (path: src: ''
                              echo mkdir -p $(dirname "$out/${path}")
                                    mkdir -p $(dirname "$out/${path}")
                              if [[ -d "${src}" ]]; then
                                echo cp -r "${src}/." "$out/${path}"
                                      cp -r "${src}/." "$out/${path}"
                              else
                                echo cp -r "${src}" "$out/${path}"
                                      cp -r "${src}" "$out/${path}"
                              fi
                              chmod -R u+w "$out/${path}"
                            '') deps # Use ${src}/. in case $out/${path} already exists, so it copies the contents to that directory.
      ) +
      # introduce files missing in git repos
      ''
        echo 'LASTCHANGE=${deps."src".rev}-refs/heads/master@{#0}'             > $out/src/build/util/LASTCHANGE
        echo '1555555555'                                                      > $out/src/build/util/LASTCHANGE.committime

        echo '/* Generated by lastchange.py, do not edit.*/'                   > $out/src/gpu/config/gpu_lists_version.h
        echo '#ifndef GPU_CONFIG_GPU_LISTS_VERSION_H_'                        >> $out/src/gpu/config/gpu_lists_version.h
        echo '#define GPU_CONFIG_GPU_LISTS_VERSION_H_'                        >> $out/src/gpu/config/gpu_lists_version.h
        echo '#define GPU_LISTS_VERSION "${deps."src".rev}"'                  >> $out/src/gpu/config/gpu_lists_version.h
        echo '#endif  // GPU_CONFIG_GPU_LISTS_VERSION_H_'                     >> $out/src/gpu/config/gpu_lists_version.h

        echo '/* Generated by lastchange.py, do not edit.*/'                   > $out/src/skia/ext/skia_commit_hash.h
        echo '#ifndef SKIA_EXT_SKIA_COMMIT_HASH_H_'                           >> $out/src/skia/ext/skia_commit_hash.h
        echo '#define SKIA_EXT_SKIA_COMMIT_HASH_H_'                           >> $out/src/skia/ext/skia_commit_hash.h
        echo '#define SKIA_COMMIT_HASH "${deps."src/third_party/skia".rev}-"' >> $out/src/skia/ext/skia_commit_hash.h
        echo '#endif  // SKIA_EXT_SKIA_COMMIT_HASH_H_'                        >> $out/src/skia/ext/skia_commit_hash.h
      '');

  # Use the prebuilt one from CIPD
  gn = stdenv.mkDerivation {
    name = "gn";
    src = deps."src/buildtools/linux64";
    nativeBuildInputs = [ autoPatchelfHook ];
    installPhase = ''
      install -Dm755 gn $out/bin/gn
    '';
  };

in stdenvNoCC.mkDerivation rec {
  pname = name;
  inherit version src;

  nativeBuildInputs = [ gn ninja pkg-config jre8 gperf bison nodejs ] ++
    # Android stuff (from src/build/install-build-deps-android.sh)
    # Including some of the stuff from src/.vpython as well
    [ bsdiff
      (python2.withPackages (p: with p; [ ply jinja2 setuptools ]))
      (python3.withPackages (p: with p; [ ply jinja2 setuptools ]))
      binutils # Needs readelf
      perl # Used by //third_party/libvpx
      buildenv
    ];

  # Even though we are building for android, it still complains if its missing linux libs/headers>..
  buildInputs = [
    dbus at-spi2-atk atk at-spi2-core nspr nss pciutils utillinux kerberos libxkbcommon
    gdk-pixbuf glib gtk3 alsaLib libXScrnSaver libXcursor libXtst libXdamage
    libdrm
  ];

  requiredSystemFeatures = [ "big-parallel" ];

  patches = lib.optional ((lib.versionAtLeast version "84") && (lib.versionOlder version "85"))
      # https://chromium-review.googlesource.com/c/chromium/src/+/2214390
      (fetchgerritpatchset {
        domain = "chromium-review.googlesource.com";
        repo = "chromium/src";
        changeNumber = 2214390;
        patchset = 2;
        sha256 = "1kk4jf2zld1pm7x5ciq3jb0k7pdc8vnpyw96jj4w77crwl5q0833";
      });


  patchFlags = [ "-p1" "-d src" ];

  # TODO: Much of the nixos-specific stuff could probably be made conditional
  postPatch = lib.optionalString (lib.versionAtLeast version "91") ''
    ( cd src
      # Required for patchShebangs (unsupported)
      chmod -x third_party/webgpu-cts/src/tools/${lib.optionalString (lib.versionAtLeast version "96") "run_"}deno
    )
  '' + ''
    ( cd src

      # `patchShebangs --build .` would fail (see https://github.com/NixOS/nixpkgs/issues/99539)
      for f in $(find . -type f -executable ! -regex '.+\.make$'); do
        patchShebangs --build "$f"
      done

      mkdir -p buildtools/linux64
      ln -s --force ${llvmPackages_11.clang.cc}/bin/clang-format buildtools/linux64/clang-format || true

      mkdir -p third_party/node/linux/node-linux-x64/bin
      ln -s --force ${nodejs}/bin/node                    third_party/node/linux/node-linux-x64/bin/node      || true

      # TODO: Have mk-vendor-file.py output this
      echo 'build_with_chromium = true'                > build/config/gclient_args.gni
      echo 'checkout_android = true'                  >> build/config/gclient_args.gni
      echo 'checkout_android_native_support = true'   >> build/config/gclient_args.gni
      echo 'checkout_google_benchmark = false'        >> build/config/gclient_args.gni
      echo 'checkout_ios_webkit = false'              >> build/config/gclient_args.gni
      echo 'checkout_nacl = false'                    >> build/config/gclient_args.gni
      echo 'checkout_oculus_sdk = false'              >> build/config/gclient_args.gni
      echo 'checkout_openxr = false'                  >> build/config/gclient_args.gni
      echo 'checkout_aemu = false'                    >> build/config/gclient_args.gni
      echo 'checkout_libaom = false'                  >> build/config/gclient_args.gni
      # Added sometime between 91.0.4472.120 and 91.0.4472.143
      echo 'generate_location_tags = false'           >> build/config/gclient_args.gni
    )
  '' + lib.optionalString enableRebranding ''
    ( cd src
      # Example from Vanadium's string-rebranding patch
      sed -ri 's/(Google )?Chrom(e|ium)/${displayName}/g' chrome/browser/touch_to_fill/android/internal/java/strings/android_touch_to_fill_strings.grd chrome/browser/ui/android/strings/android_chrome_strings.grd components/components_chromium_strings.grd components/new_or_sad_tab_strings.grdp components/security_interstitials_strings.grdp chrome/android/java/res_chromium_base/values/channel_constants.xml
      find components/strings/ -name '*.xtb' -exec sed -ri 's/(Google )?Chrom(e|ium)/${displayName}/g' {} +
      find chrome/browser/ui/android/strings/translations -name '*.xtb' -exec sed -ri 's/(Google )?Chrom(e|ium)/${displayName}/g' {} +

      sed -ri 's/Android System WebView/${displayName} Webview/g' android_webview/nonembedded/java/AndroidManifest.xml
    )
  '';

  configurePhase = ''
    # attept to fix python2 failing with "EOFError: EOF read where object expected" on multi-core builders
    export PYTHONDONTWRITEBYTECODE=true
    ( cd src
      gn gen ${lib.escapeShellArg "--args=${gnToString gnFlags}"} out/Release
    )
  '';

  # Hack: Use an FHS env. vendored android sdk/ndk and clang toolchain use it
  # https://chromium.googlesource.com/chromium/src/+/master/docs/android_build_instructions.md
  buildPhase = ''
    chromium-fhs << 'EOF'
    set -euo pipefail
    cd src
    ninja -C out/Release ${builtins.toString buildTargets} | cat
    EOF
  '';

  installPhase = ''
    ( cd src
      mkdir -p $out
      cp -r out/Release/apks/. $out/
    )
  '';
}
