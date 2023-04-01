{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;
  cfg = config.adevtool;
  adevtool = "${pkgs.adevtool}/bin/adevtool";
  buildVendorFiles =
    { buildID ? "robotnix" }:
    let
      inherit (config) device;
    in
    pkgs.runCommand "vendor-files-${device}" { } ''
      ${adevtool} download vendor/adevtool/dl/ -d ${device} -b ${buildID} -t factory ota
      ${adevtool} generate-all vendor/adevtool/config/${device}.yml -c vendor/state/${device}.json -s vendor/adevtool/dl/${device}-${buildID}-*.zip
      ${adevtool} ota-firmware vendor/adevtool/config/${device}.yml -f vendor/adevtool/dl/${device}-ota-${buildID}-*.zip

      mkdir -p $out
      cp -r ${device}/${buildID}/* $out
    '';
in
{
  options.adevtool = {
    enable = mkEnableOption "adevtool";

    buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
      default = config.apv.buildID;
    };
  };
  config = {
    build.adevtool = {
      files = buildVendorFiles {
        inherit (config.adevtool) buildID;
      };
    };
  };
}
