{ pkgs }:
let
  jdk = pkgs.callPackage (pkgs.path + /pkgs/development/compilers/openjdk/8.nix) {
    bootjdk = pkgs.callPackage (pkgs.path + /pkgs/development/compilers/openjdk/bootstrap.nix) { version = "8"; };
    inherit (pkgs.gnome2) GConf gnome_vfs;
    minimal = true;
  };
in pkgs.buildFHSUserEnv {
  name = "nixdroid-build";
  targetPkgs = pkgs: with pkgs; [
      bc
      git
      gitRepo
      gnupg
      python2
      curl
      procps
      openssl_1_0_2.dev
      # boringssl
      gnumake
      nettools
      #androidenv.platformTools
      #androidenv.androidsdk_latest
      androidenv.androidPkgs_9_0.platform-tools
      androidsdk_9_0
      jdk
      schedtool
      utillinux
      m4
      gperf
      perl
      libxml2
      zip
      unzip
      bison
      flex
      lzop
      imagemagick
      gcc
      ncurses5
      which
      rsync
      lzip

      # For android 10
      freetype # Needed by jdk9 prebuilt
      fontconfig
      python3 # Fixes failure in: soong/host/linux-x86/bin/art-apex-tester/__main__.py
    ];
  multiPkgs = pkgs: with pkgs; [ zlib ];
}
