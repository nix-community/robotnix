{ pkgs, buildPackages, lib, stdenv, fetchFromGitHub, substituteAll,
  autoPatchelfHook, addOpenGLRunpath,
  bash, grpc, xorg, libGL, mesa,
  ubootTools, openssl,
  python2, libglvnd, vulkan-loader, libdrm,
  device
}:

let
  my_ubootTools = ubootTools.overrideAttrs ({ buildInputs ? [], ... }: {
    # Weird fix for cross compilation...
    buildInputs = buildInputs ++ [ openssl ];
  });

  cuttlefish_common = stdenv.mkDerivation {
    name = "android-cuttlefish";
    version = "2020-10-26";

    src = fetchFromGitHub {
      owner = "google";
      repo = "android-cuttlefish";
      rev = "a384d3e692437583abb0b95854adc874ea63b0c3";
      sha256 = "17rhld2kvilywdamfbp3zidkxxwjbz4mviqh21wsdhgvpj3wbbv4";
    };

    preBuild = "cd host/commands/adbshell";
    postBuild = "cd ../../..";

    buildInputs = [ python2 ];

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
      source.dirs = builtins.fromJSON (builtins.readFile ./repo-master-2020-10-28.json);
      buildNumber = "2020-10-29";
      androidVersion = 12;
      envVars.ALLOW_NINJA_ENV = "true";
    } {
      source.dirs."device/google/cuttlefish".patches = [ 
        (substituteAll {
          src = ./path-fixes.patch;
          inherit cuttlefish_common;
          inherit (pkgs) bash;
        })
        ./skip-validate-host.patch
      ];
    } ];
  });

  cvd-host_package = robotnixCuttlefish.build.mkAndroid {
    name = "cvd-host_package";
    makeTargets = 
      lib.optional stdenv.isx86_64 "hosttar"
      ++ lib.optional stdenv.isAarch64 "out/soong/host/linux_bionic-arm64/cvd_host_package.tar.gz";

    # Note that it's cvd-host_package.tar.gz for x86_64 and cvd_host_package.tar.gz for aarch64, this is likely an upstream typo
    installPhase = ''
      mkdir -p $out
    '' + lib.optionalString stdenv.isx86_64 ''
      cp out/host/linux-x86/cvd-host_package.tar.gz $out/cvd-host_package.tar.gz
    '' + lib.optionalString stdenv.isAarch64 ''
      cp out/soong/host/linux_bionic-arm64/cvd_host_package.tar.gz $out/cvd-host_package.tar.gz
    '';
  };

  fixedup = stdenv.mkDerivation {
    name = "cvd-host_package";

    src = "${cvd-host_package}/cvd-host_package.tar.gz";

    nativeBuildInputs =
      lib.optionals stdenv.isx86_64 [ autoPatchelfHook addOpenGLRunpath ]
      ++ lib.optional stdenv.isAarch64 [ cuttlefish_common ]; # So nix can find the reference to this from inside the zip file
    buildInputs =
      lib.optionals stdenv.isx86_64 [ grpc xorg.libX11 libGL mesa ]
      ++ lib.optional stdenv.isAarch64 [ bash ];

    sourceRoot = ".";

    installPhase = lib.optionalString stdenv.isx86_64 ''
      rm -f bin/resize.f2fs bin/fsck.f2fs # Missing libext2_uuid-host.so under lib64/ . How would it even work normally?
      rm -rf nativetest64
      rm lib64/libgbm.so
    ''
    + ''
      rm env-vars # So we don't have unneeded references to nix store
      cp -r . $out
    ''
    + lib.optionalString stdenv.isAarch64 ''
      # For some reason, the mkenvimage built by android is for x86_64, not
      # aarch64 like the other executables.
      cp ${my_ubootTools}/bin/mkenvimage $out/bin/

      patchShebangs $out/bin/crosvm
    '';

    # This needs to be after autoPatchelfHook
    dontAutoPatchelf = stdenv.isx86_64;
    postFixup = lib.optionalString stdenv.isx86_64 ''
      autoPatchelf -- $out
      patchelf --set-rpath "${lib.makeLibraryPath [ libglvnd vulkan-loader ]}:$(patchelf --print-rpath $out/bin/detect_graphics)" $out/bin/detect_graphics
      patchelf --set-rpath "${lib.makeLibraryPath [ libdrm libglvnd vulkan-loader ]}:$(patchelf --print-rpath $out/bin/x86_64-linux-gnu/crosvm)" $out/bin/x86_64-linux-gnu/crosvm
      patchelf --set-rpath "${lib.makeLibraryPath [ libdrm libglvnd vulkan-loader ]}:$(patchelf --print-rpath $out/bin/x86_64-linux-gnu/libgfxstream_backend.so)" $out/bin/x86_64-linux-gnu/libgfxstream_backend.so
      addOpenGLRunpath $out/bin/x86_64-linux-gnu/crosvm
      addOpenGLRunpath $out/bin/x86_64-linux-gnu/libgfxstream_backend.so # TODO: Needed?
    '';

    dontFixup = stdenv.isAarch64;
  };
in {
  cvd-host_package = fixedup;
  img = robotnixCuttlefish.img;
  inherit (cuttlefish_common) src;
}
