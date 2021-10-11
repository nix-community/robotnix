{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf mkMerge mkDefault;

  # TODO: Temporary workaround for GrapheneOS 2021100606
  android12SourceDirs = (import ../../default.nix {
    inherit pkgs;
    configuration = {
      source.dirs = lib.importJSON ./repo-android-12.0.0_r2.json;
    };
  }).config.source.dirs;

  clangVersion = "r416183b";
  postRedfin = lib.elem config.deviceFamily [ "redfin" "barbet" ];

  dependencies = let
    fixupRepo = repoName: { buildInputs ? [], ... }@args: pkgs.stdenv.mkDerivation ({
      name = lib.strings.sanitizeDerivationName repoName;
      # TODO: Temporary workaround for GrapheneOS 2021100606
      #src = android12SourceDirs.${repoName}.src;
      src = config.source.dirs.${repoName}.src;
      buildInputs = with pkgs; buildInputs ++ [ autoPatchelfHook ];
      installPhase = ''
        runHook preInstall
        rm -f env-vars
        cp -r . $out
        runHook postInstall
      '';
    } // (lib.filterAttrs (n: v: n != "buildInputs") args));
  in lib.mapAttrs (n: v: fixupRepo n v) ({
    "prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9" = { buildInputs = with pkgs; [ python ]; };
    "prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9" = { buildInputs = with pkgs; [ python ]; };
    "prebuilts/clang/host/linux-x86/clang-${clangVersion}"= {
      # TODO: Temporary workaround for GrapheneOS 2021100606
      src = android12SourceDirs."prebuilts/clang/host/linux-x86".src + "/clang-${clangVersion}";
      # src = config.source.dirs."prebuilts/clang/host/linux-x86".src + "/clang-${clangVersion}";
      buildInputs = with pkgs; [
        zlib ncurses5 libedit
        stdenv.cc.cc.lib # For libstdc++.so.6
        python39 # LLDB links against this particular version of python
      ];
      postPatch = ''
        rm -r python3
      '';
    };
    "prebuilts/gas/linux-x86" = {};
    "prebuilts/misc/linux-x86" = {
      # TODO: Temporary workaround for GrapheneOS 2021100606
      src = android12SourceDirs."prebuilts/misc".src + "/linux-x86";
      #src = config.source.dirs."prebuilts/misc".src + "/linux-x86";
      buildInputs = with pkgs; [ python ];
    };
    "kernel/prebuilts/build-tools" = {
      # TODO: Temporary workaround for GrapheneOS 2021100606
      src = config.source.dirs."kernel/prebuilts/build-tools".src;
      buildInputs = with pkgs; [ python ];
      postInstall = ''
        # Workaround for patchelf not working with embedded python interpreter
        # TODO: Temporary workaround for GrapheneOS 2021100606
        cp ${android12SourceDirs."system/libufdt".src}/utils/src/mkdtboimg.py $out/linux-x86/bin
      '';
        # cp ${config.source.dirs."system/libufdt".src}/utils/src/mkdtboimg.py $out/linux-x86/bin
    };
  });

  repoName = {
    "sargo" = "crosshatch";
    "bonito" = "crosshatch";
    "bramble" = "redbull";
    "redfin" = "redbull";
  }.${config.device} or config.deviceFamily;
  sourceRelpath = "kernel/google/${repoName}";

  builtKernelName = {
    "sargo" = "bonito";
    "flame" = "coral";
  }.${config.device} or config.device;
  builtRelpath = "device/google/${builtKernelName}-kernel";

  kernel = pkgs.stdenv.mkDerivation {
    name = "grapheneos-${builtKernelName}-kernel";
    inherit (config.kernel) src patches postPatch;

    nativeBuildInputs = with pkgs; [
      perl bc nettools openssl rsync gmp libmpc mpfr lz4 which
      nukeReferences
    ] ++ lib.optionals postRedfin [
      python bison flex cpio
    ];

    preUnpack = ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "mkdir -p $(dirname ${n}); ln -s ${v} ${n}") dependencies)}

      mkdir -p $(dirname ${sourceRelpath})
      cd $(dirname ${sourceRelpath})
    '';

    prePatch = ''
      # From os-specific/linux/kernel/manual-config.nix in nixpkgs
      for mf in $(find -name Makefile -o -name Makefile.include -o -name install.sh); do
          echo "stripping FHS paths in \`$mf'..."
          sed -i "$mf" -e 's|/usr/bin/||g ; s|/bin/||g ; s|/sbin/||g'
      done
      sed -i scripts/ld-version.sh -e "s|/usr/bin/awk|${pkgs.gawk}/bin/awk|"

      if [[ -f scripts/generate_initcall_order.pl ]]; then
        patchShebangs scripts/generate_initcall_order.pl
      fi

      # Set kernel timestamp
      substituteInPlace build.sh \
        --replace "\$(git show -s --format=%ct)" "${builtins.toString config.kernel.buildDateTime}"

      sed -i '/^chrt/d' build.sh

      # TODO: Not using prebuilt clang for HOSTCC/HOSTCXX/HOSTLD, since it refers to FHS sysroot and not the sysroot from nixpkgs.
      sed -i '/HOST.*=/d' build.sh

    '' + lib.optionalString postRedfin ''
      # TODO: Remove HOSTCC / HOSTCXX. Currently, removing it makes it fail:
      # ../scripts/basic/fixdep.c:97:10: fatal error: 'sys/types.h' file not found
      sed -i '/make.*\\/a    HOSTCC=gcc \\\n    HOSTCXX=g++ \\' build.sh

    '';

    # Useful to use upstream's build.sh to catch regressions if any dependencies change
    buildPhase = let
      useCodenameArg = lib.elem config.deviceFamily [ "bonito" "crosshatch" "redfin" "barbet" ];
    in ''
      mkdir -p ../../../${builtRelpath}
      bash ./build.sh ${lib.optionalString useCodenameArg builtKernelName}
    '';

    installPhase = ''
      cp -r ../../../${builtRelpath} $out
    '';
  };
in mkIf (config.flavor == "grapheneos" && config.kernel.enable) {
  kernel.src = mkDefault config.source.dirs.${sourceRelpath}.src;
  kernel.buildDateTime = mkDefault config.source.dirs.${sourceRelpath}.dateTime;
  kernel.relpath = mkDefault builtRelpath;

  build.kernel = kernel;
}
