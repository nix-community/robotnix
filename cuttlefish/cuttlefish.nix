{ pkgs, buildPackages, lib, stdenv, fetchFromGitHub, substituteAll,
  autoPatchelfHook, addOpenGLRunpath,
  bash, grpc, xorg, libGL, mesa,
  ubootTools, openssl,
  python3, libglvnd, vulkan-loader, libdrm,
  device
}:

let
  my_ubootTools = ubootTools.overrideAttrs ({ buildInputs ? [], ... }: {
    # Weird fix for cross compilation...
    buildInputs = buildInputs ++ [ openssl ];
  });

  cuttlefish_common = stdenv.mkDerivation {
    name = "android-cuttlefish";
    version = "2021-10-15";

    src = fetchFromGitHub {
      owner = "google";
      repo = "android-cuttlefish";
      rev = "31df03a29f690298c8f893e279d510db593b5847";
      sha256 = "1hnxpzsawz8ac2x5h3gazahfs428p2wp1bfmavzgyqqy99z8pz5v";
    };

    preBuild = "cd host/commands/adbshell";
    postBuild = "cd ../../..";

    buildInputs = [ python3 ];

    installPhase = ''
      mkdir -p $out/bin/

      install -m755 host/commands/adbshell/adbshell $out/bin/
      install -m755 host/deploy/install_zip.sh $out/bin/

      install -m755 host/deploy/unpack_boot_image.py $out/bin/
      install -m755 host/deploy/capability_query.py $out/bin/
    '';
  };

  robotnixCuttlefish = (import ../default.nix {
    configuration = lib.mkMerge [ {
      inherit device;
      variant = "userdebug";
      source.dirs = builtins.fromJSON (builtins.readFile ./repo-android-12.0.0_r2.json);
      buildNumber = "2021-10-15";
      androidVersion = 12;
    } {
      source.dirs."device/google/cuttlefish" = {
        patches = [ 
          ./0001-Hack-to-always-validate-host.patch
        ];
        postPatch = ''
          substituteInPlace common/libs/utils/network.cpp \
              --replace '/bin/bash' '${pkgs.bash}/bin/bash'

          substituteInPlace host/commands/assemble_cvd/boot_image_utils.cc \
              --replace '/bin/bash' '${pkgs.bash}/bin/bash'

          substituteInPlace common/libs/utils/archive.cpp \
              --replace '/usr/bin/bsdtar' '${pkgs.libarchive}/bin/bsdtar'

          substituteInPlace host/libs/config/cuttlefish_config.cpp \
              --replace '/usr/lib/cuttlefish-common' '${cuttlefish_common}'
        '';
      };

      # TODO: Figure out why it crashes if this hack to not use URingExecutor is not used
      source.dirs."external/crosvm".patches = [
        ./crosvm-hack.patch
      ];
    } ];
  });

  cvd-host_package = robotnixCuttlefish.config.build.mkAndroid {
    name = "cvd-host_package";
    makeTargets = 
      lib.optional stdenv.isx86_64 "hosttar"
      ++ lib.optional stdenv.isAarch64 "out/soong/host/linux_bionic-arm64/cvd-host_package.tar.gz";

    installPhase = let
      host = if stdenv.isx86_64 then "linux-x86"
        else if stdenv.isAarch64 then "linux_bionic-arm64"
        else throw "AOSP build system does not support selected architecture";
    in ''
      mkdir -p $out
      cp out/soong/host/${host}/cvd-host_package.tar.gz $out/cvd-host_package.tar.gz
    '';
  };

  fixedup = stdenv.mkDerivation {
    name = "cvd-host_package";

    src = "${cvd-host_package}/cvd-host_package.tar.gz";

    nativeBuildInputs =
      [ cuttlefish_common ] # So nix can find the reference to this from inside the zip file
      ++ lib.optionals stdenv.isx86_64 [ autoPatchelfHook addOpenGLRunpath ];
    buildInputs =
      lib.optionals stdenv.isx86_64 [ xorg.libX11 libGL mesa ]
      ++ lib.optional stdenv.isAarch64 [ bash ];

    sourceRoot = ".";

    installPhase = ''
      cp -r . $out

      for file in $out/bin/* $out/bin/x86_64-linux-gnu/crosvm; do
        isELF "$file" || continue
        bash ${../scripts/patchelf-prefix.sh} "$file" "${stdenv.cc.bintools.dynamicLinker}" || continue
      done
      patchelf \
        --set-rpath "${lib.makeLibraryPath [ libdrm ]}:$(patchelf --print-rpath bin/x86_64-linux-gnu/crosvm)" \
        $out/bin/x86_64-linux-gnu/crosvm
      addOpenGLRunpath $out/bin/x86_64-linux-gnu/crosvm
      patchShebangs $out/bin/crosvm
    ''
    + lib.optionalString stdenv.isAarch64 ''
      # For some reason, the mkenvimage built by android is for x86_64, not
      # aarch64 like the other executables.
      cp ${my_ubootTools}/bin/mkenvimage $out/bin/
    '';

    dontFixup = true;
    dontStrip = true;
    dontMoveLib64 = true;
    noDumpEnvVars = true;
    dontAutoPatchelf = true;
  };
in {
  cvd-host_package = fixedup;
  img = robotnixCuttlefish.img;
  inherit (cuttlefish_common) src;
}
