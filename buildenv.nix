{ pkgs ? import <nixpkgs> {} }:
 
let
  jdk =  pkgs.callPackage <nixpkgs/pkgs/development/compilers/openjdk/8.nix> {
    bootjdk = pkgs.callPackage <nixpkgs/pkgs/development/compilers/openjdk/bootstrap.nix> { version = "8"; };
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
      # androidenv.buildTools
      androidenv.platformTools
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
    ];
  multiPkgs = pkgs: with pkgs; [ zlib ];
}
