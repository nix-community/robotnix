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
  sepolicyDirNames = lib.filter (d: lib.hasSuffix "-sepolicy" d) (lib.attrNames config.source.dirs);
  unpackPhase =
    let
      unpackDirNames = lib.filter
        (d:
          !(lib.elem d ([ "vendor/adevtool" "vendor/google_devices/${config.device}" ]))
          && !(lib.hasPrefix "kernel/android" d))
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
        ${unpackPhase}
      '';
      nativeBuildInputs = with pkgs; [ unzip ];
      buildPhase = ''
        set -ex
        cp ${img}/${device}-${lib.toLower buildID}-*.zip img.zip
        cp ${img}/${device}-ota-${lib.toLower buildID}-*.zip ota.zip

        ${adevtool} generate-all \
          vendor/adevtool/config/${device}.yml \
          -c vendor/state/${device}.json \
          -s img.zip \
          -a ${pkgs.robotnix.build-tools}/aapt2

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
    build.adevtool = rec {
      img = fetchImage {
        inherit (config) device;
        inherit (cfg) hash buildID;
      };
      files = unpackImg {
        inherit (config) device deviceFamily;
        inherit (cfg) buildID;
        inherit img;
      };

      patchPhase = lib.optionalString cfg.enable ''
        export HOME=$(pwd)
        ${lib.concatMapStringsSep "\n"
          (name: ''
            ${pkgs.utillinux}/bin/umount ${config.source.dirs.${name}.relpath}
            rmdir ${config.source.dirs.${name}.relpath}
            cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.source.dirs.${name}.src} ${config.source.dirs.${name}.relpath}
            chmod u+w -R ${config.source.dirs.${name}.relpath}
          '')
          sepolicyDirNames}

        cp -r ${config.build.adevtool.img}/${config.device}-${lib.toLower cfg.buildID}-*.zip img.zip
        ${adevtool} \
          fix-certs \
          -s  img.zip \
          -d ${config.device} \
          -p ${lib.concatStringsSep " " sepolicyDirNames}
      '';
    };
    source.dirs = mkIf cfg.enable {
      "vendor/google_devices/${config.device}".src = config.build.adevtool.files;
    };
  };
}
