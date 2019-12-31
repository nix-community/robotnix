{ config, pkgs, lib, ... }:

let
  oldnixpkgs = builtins.fetchTarball { # nixos 13.10 for super old glibc 2.17
    url = "https://github.com/nixos/nixpkgs/archive/91e952ab1e6e3d249ff201f915b38f7ab34e8c3f.tar.gz";
    sha256 = "0i8jxljrqw6f62vacmabmbxrw8wf2db4118vj1kd7mkqgdbpjpd7";
  };
  glibc217 = (import oldnixpkgs {}).glibc;
in
with lib;
{
  options = {
    source = {
      overridePrebuilts = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf config.source.overridePrebuilts {
    source.dirs."build/soong".patches = [ ./disable-fail-warnings.patch ];
    # Otherwise fails with prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot/include/features.h:381:4: error: _FORTIFY_SOURCE requires compiling with optimization (-O) [-Werror,-W#warnings]
    # Our features.h sets this warning and clang doesn't set __OPTIMIZE__ ?
    source.dirs."prebuilts/go/linux-x86".contents = "${pkgs.go}/share/go"; # Seems to work
    source.dirs."prebuilts/python/linux-x86/2.7.5".contents = python27.withPackages (p: with p;
      [ selinux 
      # TODO: Probably needs a bunch more
      ]
    );
    source.dirs."prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8".contents =
      pkgs.symlinkJoin {
        name = "x86_64-linux-glibc2.17-4.8";
        paths = with pkgs; [ gcc49 glibc ]; # cloog? # gcc_debug? isl? binutils_unwrapped? Might not even need glibc if all other binaries use the /nix/ version anyway?
#        postBuild = let
#          sysroot = pkgs.symlinkJoin {
#            name = "gcc-sysroot";
#            paths = with pkgs; [ # Try to match the packages in PACKAGE_SOURCES
#              acl
#              #acl.dev
#              audiofile
#              #audiofile.dev
#              glibc217 #glibc.dev
#              ncurses5
#              ncurses5.dev
#            ];
#          };
#        in "ln -s ${sysroot} $out/sysroot"; # Put under sysroot/usr to match upstream?
      };
#    source.dirs."prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9".contents =
#      with pkgs.pkgsCross.aarch64-android-prebuilt.buildPackages; gcc49;
    # TODO Need to get the right ndk version and all that

    #source.dirs."prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9".contents = pkgsCross.aarch64-android-prebuilt.stdenv.cc;

    source.dirs."prebuilts/clang/host/linux-x86".contents = pkgs.runCommand "clang" {} ''
      mkdir $out
      ln -s ${pkgs.clang_8} $out/clang-r353983b
    '';

    # AOSP source also has a build-prebuilts.sh script which uses AOSP's build
    # system to rebuild their prebuilts--indirectly using their prebuilts of course.
#    source.dirs."prebuilts/build-tools".postPatch = ''
#      
#    '';
  };
}
