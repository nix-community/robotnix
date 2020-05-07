{ config, pkgs, lib, ... }:
with lib;
let
  deviceMetadata = importJSON ./device-metadata.json;
  deviceDirs = importJSON ./device-dirs.json;
  vendorDirs = importJSON ./vendor-dirs.json;

  # TODO: Move this filtering into vanilla/graphene
  filterDirAttrs = dir: filterAttrs (n: v: elem n ["rev" "sha256" "url"]) dir;
  filterDirsAttrs = dirs: mapAttrs (n: v: filterDirAttrs v) dirs;

  date = "2020.05.04";
  LineageOSRelease = "lineage-17.1";
in mkIf (config.flavor == "lineageos") (mkMerge [
{
  productNamePrefix = "lineage"; # product names start with "lineage_"

  # FIXME: what should it be for the following?
  buildNumber = mkDefault date;
  buildDateTime = mkDefault 1588648528;
  #vendor.buildID = mkDefault "lineage-17.0-${date}";

  source.dirs = lib.importJSON (./. + "/${LineageOSRelease}.json");

  source.manifest.url = mkDefault "https://github.com/LineageOS/android.git";
  source.manifest.rev = mkDefault "refs/heads/${LineageOSRelease}";
}
{
  # Device-specific source dirs
  source.dirs =
    let
      relpaths = map (d: replaceStrings ["_"] ["/"] (removePrefix "android_" d)) deviceMetadata.${config.device}.deps;
    in filterDirsAttrs (getAttrs relpaths deviceDirs);
}
{
  # Vendor-specific source dirs
  source.dirs =
    let
      oem = toLower deviceMetadata.${config.device}.oem;
      relpath = "vendor/${if oem == "lg" then "lge" else oem}";
    in filterDirsAttrs (getAttrs [relpath] vendorDirs);
}
])
