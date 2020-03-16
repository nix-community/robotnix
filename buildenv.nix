{ pkgs }:
pkgs.buildFHSUserEnv {
  name = "robotnix-build";
  targetPkgs = pkgs: with pkgs; [
      # TODO: Much of this can propbably be removed with android 10
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
      (androidPkgs.sdk (p: with p.stable; [ tools platform-tools ]))
      #androidsdk_9_0
      jre8_headless
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
