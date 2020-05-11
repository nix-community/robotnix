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
in mkIf (config.flavor == "lineageos")
{
  productNamePrefix = "lineage"; # product names start with "lineage_"

  # FIXME: what should it be for the following?
  buildNumber = mkDefault date;
  buildDateTime = mkDefault 1588648528;
  #vendor.buildID = mkDefault "lineage-17.0-${date}";

  source.dirs = mkMerge ([
    (lib.importJSON (./. + "/repo-${LineageOSRelease}.json"))

    {
      "vendor/lineage".patches = [
        ./0001-Remove-LineageOS-keys.patch
        (pkgs.substituteAll {
          src = ./0002-bootanimation-Reproducibility-fix.patch;
          inherit (pkgs) imagemagick;
        })
      ];
      "system/extras".patches = [
        # pkgutil.get_data() not working, probably because we don't use their compiled python
        (pkgs.fetchpatch {
          url = "https://github.com/LineageOS/android_system_extras/commit/7da4b29321eb7ebce9eb9a43d0fbd85d0aa1e870.patch";
          sha256 = "0pv56lypdpsn66s7ffcps5ykyfx0hjkazml89flj7p1px12zjhy1";
          revert = true;
        })
      ];
    }
  ] ++ optionals (deviceMetadata ? "${config.device}") [
    # Device-specific source dirs
    (let
      relpaths = map (d: replaceStrings ["_"] ["/"] (removePrefix "android_" d)) deviceMetadata.${config.device}.deps;
    in filterDirsAttrs (getAttrs relpaths deviceDirs))

    # Vendor-specific source dirs
    (let
      oem = toLower deviceMetadata.${config.device}.oem;
      relpath = "vendor/${if oem == "lg" then "lge" else oem}";
    in filterDirsAttrs (getAttrs [relpath] vendorDirs))
  ]);

  source.manifest.url = mkDefault "https://github.com/LineageOS/android.git";
  source.manifest.rev = mkDefault "refs/heads/${LineageOSRelease}";

  envPackages = [ pkgs.openssl.dev ]; # Needed by included kernel build for some devices (pioneer at least)
}
