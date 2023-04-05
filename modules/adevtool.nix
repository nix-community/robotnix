{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;
  cfg = config.adevtool;
  adevtoolPkg = pkgs.adevtool config.source.dirs."vendor/adevtool".src;
  adevtool = "${adevtoolPkg}/bin/adevtool";
  fetchImage = { hash ? lib.fakeSha256, device, buildID }:
    pkgs.stdenv.mkDerivation {
      name = "fetch-vendor-firmware";
      src = pkgs.emptyDirectory;
      installPhase = ''
        mkdir -p $out
        export HOME=$(pwd)
        ${adevtool} download $out -d ${device} -b ${buildID} -t factory ota | cat
      '';

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = hash;
    };
  unpackPhase =
    let
      unpackDirNames = lib.filter
        (d: (
          !(lib.elem d [ "vendor/adevtool" "vendor/google_devices/${config.device}" ])
          && !(lib.hasPrefix "kernel/android" d)
        ))
        (lib.attrNames config.source.dirs);
      unpackDirs = lib.attrVals unpackDirNames config.source.dirs;
    in
    pkgs.writeTextFile {
      name = "unpack-sources-for-adevtool";
      executable = true;
      text = ''
        mkdir -p vendor/adevtool
        mount --bind ${adevtoolPkg + /libexec/adevtool/deps/adevtool} vendor/adevtool
      '' + (lib.concatMapStringsSep "\n" (dir: dir.unpackScript) unpackDirs);
    };
  unpackImg = { img, device ? config.device, deviceFamily ? config.deviceFamily, buildID ? cfg.buildID }:
    config.build.mkAndroid {
      name = "unpack-img-${device}-${buildID}";
      unpackPhase = ''
        runHook preUnpack
        ${unpackPhase}
        runHook postUnpack
      '';
      nativeBuildInputs = with pkgs; [ unzip ];
      buildPhase = ''
        set -e
        export HOME=$(pwd)
        source build/envsetup.sh
        m aapt2

        cp ${img}/${device}-${lib.toLower buildID}-*.zip img.zip
        cp ${img}/${device}-ota-${lib.toLower buildID}-*.zip ota.zip

        ${adevtool} generate-all \
          vendor/adevtool/config/${device}.yml \
          -c vendor/state/${device}.json \
          -s img.zip

        ${adevtool} ota-firmware \
          vendor/adevtool/config/${device}.yml \
          -f ota.zip
      '';

      installPhase = ''
        mkdir -p $out
        cp -r vendor/google_devices/${device}/* $out
      '';
    };
in
{
  options.adevtool = {
    enable = mkEnableOption "adevtool";

    buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
      default = config.apv.buildID;
    };

    hash = mkOption {
      type = types.str;
      description = "Downloaded sha256 hash of the ota files. Unset to redownload.";
      default = lib.fakeSha256;
    };
  };
  config = {
    build.adevtool = {
      files = unpackImg rec {
        inherit (config) device deviceFamily;
        inherit (cfg) buildID;
        img = fetchImage {
          inherit device buildID;
          inherit (cfg) hash;
        };
      };
    };
    source.dirs = mkIf cfg.enable {
      "vendor/google_devices/${config.device}".src = config.build.adevtool.files;
    };
  };
}
