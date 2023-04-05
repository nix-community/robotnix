{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf mkMerge mkDefault;

  clangVersion = "r450784e";
  postRedfin = lib.elem config.deviceFamily [ "redfin" "barbet" "raviole" "bluejay" "pantah" ];
  postRaviole = lib.elem config.deviceFamily [ "raviole" "bluejay" "pantah" ];
  buildScriptFor = {
    "coral" = "build/build.sh";
    "sunfish" = "build/build.sh";
    "redbull" = "build/build.sh";
    "raviole" = "build_slider.sh";
    "bluejay" = "build_bluejay.sh";
    "pantah" = "build_cloudripper.sh";
  };
  buildScript = if (config.androidVersion >= 13) then buildScriptFor.${config.deviceFamily} else "build.sh";
  realBuildScript = if (config.androidVersion >= 13) then "build/build.sh" else "build.sh";
  kernelPrefix = if (config.androidVersion >= 13) then "kernel/android" else "kernel/google";
  grapheneOSRelease = "${config.apv.buildID}.${config.buildNumber}";

  buildConfigVar = "private/msm-google/build.config.${config.deviceFamily}";
  subPaths = prefix: (lib.filter (name: (lib.hasPrefix prefix name)) (lib.attrNames config.source.dirs));
  kernelSources = subPaths sourceRelpath;
  unpackSrc = name: src: ''
    mkdir -p $(dirname ${name})
    cp -r ${src} ${name}
  '';
  linkSrc = name: c: lib.optionalString (lib.hasAttr "linkfiles" c) (lib.concatStringsSep "\n" (map
    ({ src, dest }: ''
      mkdir -p $(dirname ${sourceRelpath}/${dest})
      ln -rs ${name}/${src} ${sourceRelpath}/${dest}
    '')
    c.linkfiles));
  copySrc = name: c: lib.optionalString (lib.hasAttr "copyfiles" c) (lib.concatStringsSep "\n" (map
    ({ src, dest }: ''
      mkdir -p $(dirname ${sourceRelpath}/${dest})
      cp -r ${name}/${src} ${sourceRelpath}/${dest}
    '')
    c.copyfiles));
  unpackCmd = name: c: lib.concatStringsSep "\n" [ (unpackSrc name c.src) (linkSrc name c) (copySrc name c) ];
  unpackSrcs = sources: (lib.concatStringsSep "\n"
    (lib.mapAttrsToList unpackCmd (lib.filterAttrs (name: src: (lib.elem name sources)) config.source.dirs)));

  # the kernel build scripts deeply assume clang as of android 13
  llvm = pkgs.llvmPackages_13;
  stdenv = if (config.androidVersion >= 13) then pkgs.stdenv else pkgs.stdenv;
  dependenciesPre =
    let
      fixupRepo = repoName: { buildInputs ? [ ], ... }@args: stdenv.mkDerivation ({
        name = lib.strings.sanitizeDerivationName repoName;
        src = config.source.dirs.${repoName}.src;
        buildInputs = with pkgs; buildInputs ++ [ autoPatchelfHook ];
        installPhase = ''
          runHook preInstall
          rm -f env-vars
          mkdir -p $out
          cp -r . $out
          runHook postInstall
        '';
      } // (lib.filterAttrs (n: v: n != "buildInputs") args));
    in
    lib.mapAttrs (n: v: fixupRepo n v) (if (config.androidVersion <= 12) then {
      "prebuilts/clang/host/linux-x86/clang-${clangVersion}" = {
        src = config.source.dirs."prebuilts/clang/host/linux-x86".src + "/clang-${clangVersion}";
        buildInputs = with pkgs; [
          zlib
          ncurses5
          libedit
          stdenv.cc.cc.lib # For libstdc++.so.6
          python39 # LLDB links against this particular version of python
        ];
        postPatch = ''
          rm -r python3
        '';
      };
      "prebuilts/misc/linux-x86" = {
        src = config.source.dirs."prebuilts/misc".src + "/linux-x86";
        buildInputs = with pkgs; [ python ];
      };
      "kernel/prebuilts/build-tools" = {
        src = config.source.dirs."prebuilts/build-tools".src;
        buildInputs = with pkgs; [ python ];
        postInstall = ''
          # Workaround for patchelf not working with embedded python interpreter
          cp ${config.source.dirs."system/libufdt".src}/utils/src/mkdtboimg.py $out/linux-x86/bin
        '';
      };
      "prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9" = { buildInputs = with pkgs; [ python ]; };
      "prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9" = { buildInputs = with pkgs; [ python ]; };
      "prebuilts/gas/linux-x86" = { };
    } else {
      "${sourceRelpath}/prebuilts/clang/host/linux-x86/clang-${clangVersion}" = {
        src = config.source.dirs."${sourceRelpath}/prebuilts/clang/host/linux-x86".src + "/clang-${clangVersion}";
        buildInputs = with pkgs; [
          zlib
          ncurses5
          libedit
          stdenv.cc.cc.lib # For libstdc++.so.6
          python39 # LLDB links against this particular version of python
          musl
        ];
        postPatch = ''
          rm -r python3
        '';
        postInstall = ''
          mkdir -p $out/lib
          ln -s ${pkgs.musl}/lib/libc.so $out/lib/libc_musl.so
          addAutoPatchelfSearchPath $out
        '';
      };
      "${sourceRelpath}/prebuilts/misc/linux-x86" = {
        src = config.source.dirs."${sourceRelpath}/prebuilts/misc".src + "/linux-x86";
        buildInputs = with pkgs; [ python ];
      };
      # these need to be rebuilt entirely
      "${sourceRelpath}/prebuilts/build-tools" = rec {
        srcs = config.source.dirs."${sourceRelpath}/prebuilts/build-tools".src;
        nativeBuildInputs = with pkgs;
          [
            pkgs.autoPatchelfHook
            stdenv.cc.cc.lib
            musl
          ];
        preInstall = ''
          mkdir -p $out/lib
          ln -s ${pkgs.musl}/lib/libc.so $out/lib/libc_musl.so
          rm path/linux-x86/python
          ln -s ${pkgs.python3}/bin/python3 path/linux-x86/python
        '';
        postInstall = ''
          # Workaround for patchelf not working with embedded python interpreter
          cp ${config.source.dirs."system/libufdt".src}/utils/src/mkdtboimg.py $out/linux-x86/bin
          addAutoPatchelfSearchPath $out/linux-x86
          # make sure we only patchelf binaries
          autoPatchelf $out/path/linux-x86 $out/linux-x86/bin
        '';
        dontPatchelf = true;
      };
      "${sourceRelpath}/prebuilts/gas/linux-x86" = {
        src = config.source.dirs."${sourceRelpath}/prebuilts/gas/linux-x86".src;
      };
      "${sourceRelpath}/prebuilts/kernel-build-tools" =
        let
          build_image = pkgs.python39Packages.buildPythonPackage {
            pname = "grapheneos-build_image";
            version = grapheneOSRelease;
            src = config.source.dirs."build/make".src + /tools/releasetools;
            format = "other";
            installPhase = ''
              mkdir -p $out/lib/python3.9/site-packages/ $out/bin
              cp -r *.py $out/lib/python3.9/site-packages/
              cp build_image.py $out/bin/build_image
              chmod +x $out/bin/build_image
            '';
            doCheck = false;
          };
          ext4-utils = pkgs.python39Packages.buildPythonPackage {
            pname = "grapheneos-ext4-utils";
            version = grapheneOSRelease;
            src = config.source.dirs."system/extras".src + /ext4_utils;
            nativeBuildInputs = with pkgs; [ autoPatchelfHook ];
            format = "other";
            installPhase = ''
              mkdir -p $out/lib/python3.9/site-packages $out/bin
              cp mkuserimg_mke2fs.py $out/lib/python3.9/site-packages
              cp mke2fs.conf $out/lib/python3.9/site-packages
              ln -s $out/lib/python3.9/site-packages/mkuserimg_mke2fs.py $out/bin/mkuserimg_mke2fs
              chmod +x $out/bin/mkuserimg_mke2fs
            '';
          };
          avb = pkgs.python39Packages.buildPythonPackage {
            pname = "grapheneos-avb";
            version = grapheneOSRelease;
            src = config.source.dirs."external/avb".src;
            format = "other";
            installPhase = ''
              mkdir -p $out/lib/python3.9/site-packages/ $out/bin
              cp -r avbtool.py $out/lib/python3.9/site-packages/
              ln -s $out/lib/python3.9/site-packages/avbtool.py $out/bin/avbtool
              chmod +x $out/bin/avbtool
            '';
            doCheck = false;
          };
          certify_bootimg = pkgs.python39Packages.buildPythonPackage {
            pname = "grapheneos-certify_bootimg";
            version = grapheneOSRelease;
            src = config.source.dirs."${sourceRelpath}/tools/mkbootimg".src;
            format = "other";
            installPhase = ''
              mkdir -p $out/lib/python3.9/site-packages $out/bin
              cp -r gki/ $out/lib/python3.9/site-packages
              cp unpack_bootimg.py $out/lib/python3.9/site-packages
              cp repack_bootimg.py $out/lib/python3.9/site-packages
              ln -s $out/lib/python3.9/site-packages/gki/certify_bootimg.py $out/bin/certify_bootimg
              chmod +x $out/bin/certify_bootimg
            '';
            doCheck = false;
          };
          release-tools-py = (pkgs.python39.withPackages (ps: [
            build_image
            ext4-utils
            avb
            certify_bootimg
          ])).override {
            makeWrapperArgs = [ "--set PYTHONHOME $out" "--set PYTHONPATH $out" ];
          };
        in
        {
          src = config.source.dirs."${sourceRelpath}/prebuilts/kernel-build-tools".src;
          nativeBuildInputs = with pkgs; [ release-tools-py makeWrapper ];
          postInstall = ''
            # Workaround for patchelf not working with embedded python interpreter
            ln -sf ${release-tools-py}/bin/build_image $out/linux-x86/bin/build_image
            ln -sf ${release-tools-py}/bin/mkuserimg_mke2fs $out/linux-x86/bin/mkuserimg_mke2fs
            ln -sf ${release-tools-py}/bin/avbtool $out/linux-x86/bin/avbtool
            ln -sf ${release-tools-py}/bin/certify_bootimg $out/linux-x86/bin/certify_bootimg
            ls -l ${release-tools-py}/bin
          '';
        };
    });

  # ugly hack to make sure patchelf finds liblog.so
  dependencies = dependenciesPre // (
    let
      build-tools = dependenciesPre."${sourceRelpath}/prebuilts/build-tools";
    in
    {
      "${sourceRelpath}/prebuilts/clang/host/linux-x86/clang-${clangVersion}" =
        (lib.getAttr "${sourceRelpath}/prebuilts/clang/host/linux-x86/clang-${clangVersion}" dependenciesPre).overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ (with pkgs; [ patchelf ]);
          preFixup = ''
            addAutoPatchelfSearchPath ${build-tools}/linux-x86/lib64
          '';
        });
    }
  );

  repoName = {
    "sargo" = "crosshatch";
    "bonito" = "crosshatch";
    "sunfish" = "coral";
    "bramble" = "redbull";
    "redfin" = "redbull";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.deviceFamily;
  sourceRelpath = "${kernelPrefix}/${repoName}";

  builtKernelName = {
    "sargo" = "bonito";
    "flame" = "coral";
    "sunfish" = "coral";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.device;
  builtRelpath = "device/google/${builtKernelName}-kernel";

  kernel =
    let
      openssl' = pkgs.openssl;
      pkgsCross = pkgs.unstable.pkgsCross.aarch64-android-prebuilt;
      android-stdenv = pkgsCross.gccCrossLibcStdenv;
      android-bintools = android-stdenv.cc.bintools.bintools_bin;
      android-gcc = android-stdenv.cc;
    in
    stdenv.mkDerivation (rec {
      name = "grapheneos-${builtKernelName}-kernel";
      inherit (config.kernel) patches postPatch;

      src = pkgs.emptyDirectory;
      sourceRoot = ".";
      nativeBuildInputs = with pkgs; [
        perl
        bc
        nettools
        openssl'
        openssl'.out
        rsync
        gmp
        libmpc
        mpfr
        lz4
        which
        nukeReferences
        ripgrep
        glibc.dev.dev.dev
        pkg-config
        autoPatchelfHook
        coreutils
        gawk
      ] ++ lib.optionals postRedfin [
        python3
        bison
        flex
        cpio
      ] ++ lib.optionals postRaviole [
        git
        zlib
        elfutils
      ];

      preUnpack = ''
        shopt -s dotglob
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "mkdir -p $(dirname ${n}); ln -s ${v} ${n}") dependencies)}
        ${unpackSrcs (lib.filter
          (name: !lib.any (depName: lib.hasPrefix name depName) (lib.attrNames dependencies))
          kernelSources)}
      '';

      postUnpack = "cd ${sourceRelpath}";

      prePatch = ''
        set -exo pipefail
        ls -l --color=always build build/kernel prebuilts

        # From os-specific/linux/kernel/manual-config.nix in nixpkgs
        for mf in $(find -name Makefile -o -name Makefile.include -o -name install.sh); do
            echo "stripping FHS paths in \`$mf'..."
            sed -i "$mf" -e 's|/usr/bin/||g ; s|/bin/||g ; s|/sbin/||g'
        done
        if [[ -e scripts/ld-version.sh ]]; then
          sed -i scripts/ld-version.sh -e "s|/usr/bin/awk|${pkgs.gawk}/bin/awk|"
        fi

        # Set kernel timestamp
        substituteInPlace ${realBuildScript} \
          --replace "\$(git show -s --format=%ct)" "${builtins.toString config.kernel.buildDateTime}"

        sed -i '/^chrt/d' ${realBuildScript}

        # TODO: Not using prebuilt clang for HOSTCC/HOSTCXX/HOSTLD, since it refers to FHS sysroot and not the sysroot from nixpkgs.
        sed -i '/HOST.*=/d' ${realBuildScript}

        # nixpkgs-21.11 patchShebangs can't handle /usr/bin/env so replace it with a newer version that can.
        unset -f patchShebangs
        source ${../../scripts/patch-shebangs.sh}

        if [[ -f scripts/generate_initcall_order.pl ]]; then
          patchShebangs --build scripts/generate_initcall_order.pl
        fi

        patchShebangs --build ${buildScript} ${realBuildScript}
        if [[ -d private/gs-google ]]; then
          patchShebangs --build private/gs-google/
        fi
        if [[ -d aosp/ ]]; then
          patchShebangs --build aosp/
        fi
        if [[ -f tools/mkbootimg/mkbootimg.py ]]; then
          patchShebangs --build tools/mkbootimg/mkbootimg.py
        fi
        for f in build*/*; do
          patchShebangs --build $(realpath $f)
        done

        echo "echo $(pwd)" > build/gettop.sh && chmod +x build/gettop.sh
      '' + lib.optionalString (postRedfin && config.androidVersion <= 12) ''
        # TODO: Remove HOSTCC / HOSTCXX. Currently, removing it makes it fail:
        # ../scripts/basic/fixdep.c:97:10: fatal error: 'sys/types.h' file not found
        sed -i '/make.*\\/a    HOSTCC=gcc \\\n    HOSTCXX=g++ \\' build/build.sh

      '' + lib.optionalString (config.androidVersion >= 13) ''
        # don't pass clang/lld only flags
        sed -i '/LLD_COMPILER_RT.*/d' build/_setup_env.sh

        # make sure we can set all the toolchain components
        sed -s -i '/LLVM=1/d' build/_setup_env.sh build/kernel/_setup_env.sh aosp/build.config.common private/gs-google/build.config.common

        # by default, shell hooks are set up to validate that the config generated at the start of the build matches the one in the tree.
        # this is meant to ensure changes are committed back but we don't care -- errors because the config changed don't matter to us.
        sed -s -i 's/POST_DEFCONFIG_CMDS="check_defconfig"/POST_DEFCONFIG_CMDS=""/' private/gs-google/build.config.gki aosp/build.config.gki
        sed -s -i 's/POST_DEFCONFIG_CMDS="check_defconfig && /POST_DEFCONFIG_CMDS="/' private/gs-google/build.config.gki_kasan aosp/build.config.gki_kprobes private/gs-google/build.config.gki_kprobes private/gs-google/build.config.gki_kasan

        # make sure system tools are preferred over the prebuilt toolchain
        sed -i "s|export PATH$|export PATH=$PATH:\$PATH|" build/_setup_env.sh

        # make sure a separate LD is passed for target vs build platforms
        sed -i 's/tool_args+=("LD=''${LD}" "HOSTLD=''${LD}")/tool_args+=("LD=''${LD}" "HOSTLD=''${HOSTLD}")/' build/_setup_env.sh
        sed -i 's/KCFLAGS=-Werror/KCFLAGS=-w/' private/gs-google/build_mixed.sh

        # remove a clang only syntax extension so we can build with gcc
        find private/google-modules -type f -name '*.h' -exec sed -E -i 's/enum ([[:alnum:]_]+) : ([[:alnum:]_]+) \{/enum \1 {/' '{}' \;

        # this cflag throws an error on gcc and there's an open PR that says it should throw an error on clang as well.
        sed -i '/EXTRA_CFLAGS.*/aCFLAGS_REMOVE_aoc_alsa_hw.o += -mgeneral-regs-only' private/google-modules/aoc/alsa/Makefile
      '';

      # Useful to use upstream's build.sh to catch regressions if any dependencies change
      # TODO: add KBUILD env vars for pre-raviole on android 13
      preBuild = ''
        mkdir -p ../../../${builtRelpath} out
        chmod a+w -R ../../../${builtRelpath} out
      '';

      buildPhase =
        let
          useCodenameArg = config.androidVersion <= 12;
          CFLAGS = "'-isystem ${pkgs.glibc.dev.dev.dev} -L${openssl'.out}/lib'";
        in
        ''
          runHook preBuild

          LLVM="" CC=${android-gcc}/bin/aarch64-unknown-linux-android-cc HOSTCC=gcc HOSTCXX=g++ \
            LD=${android-bintools}/bin/aarch64-unknown-linux-android-ld HOSTLD=ld \
            STRIP=${android-bintools}/bin/aarch64-unknown-linux-android-strip \
            OBJCOPY=${android-bintools}/bin/aarch64-unknown-linux-android-objcopy \
            OBJDUMP=${android-bintools}/bin/aarch64-unknown-linux-android-objdump \
            AR=${android-bintools}/bin/aarch64-unknown-linux-android-ar \
            AS=${android-bintools}/bin/aarch64-unknown-linux-android-as \
            NM=${android-bintools}/bin/aarch64-unknown-linux-android-nm \
            KBUILD_MODPOST_WARN=1 \
            ${if postRaviole then "LTO=full BUILD_AOSP_KERNEL=1" else "BUILD_CONFIG=${buildConfigVar}"} \
            ./${buildScript} \
            STRIP=${android-bintools}/bin/aarch64-unknown-linux-android-strip \
            DTC_FLAGS='-Wno-reg_format -Wno-avoid_default_addr_size -Wno-unit_address_vs_reg -Wno-graph_child_address -Wno-unit_address_format -Wno-interrupt_provider -@' \
            ${lib.optionalString useCodenameArg builtKernelName}

          runHook postBuild
        '';

      postBuild = ''
        cp -r out/mixed/dist/* ../../../${builtRelpath}
      '';

      installPhase = ''
        cp -r ../../../${builtRelpath} $out
      '';
    });

in
mkIf (config.flavor == "grapheneos" && config.kernel.enable) (mkMerge [
  {
    kernel.name = kernel.name;
    kernel.src = pkgs.writeShellScript "unused" "true";
    kernel.buildDateTime = mkDefault config.source.dirs.${sourceRelpath}.dateTime;
    kernel.relpath = mkDefault builtRelpath;

    build.kernel = kernel;
  }
])
