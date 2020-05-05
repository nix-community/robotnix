{ config, pkgs, lib, ... }:
with lib;
let
  date = "2020.05.04";
  LineageOSRelease = "lineage-17.0";
in mkIf (config.flavor == "lineageos") (mkMerge [
{
  # FIXME: what should it be for the following?
  buildNumber = mkDefault date;
  buildDateTime = mkDefault 1588648528;
  vendor.buildID = mkDefault "lineage-17.0-${date}";

  source.dirs = lib.importJSON (./. + "/${LineageOSRelease}.json");

  source.manifest.url = mkDefault "https://github.com/LineageOS/android.git";
  source.manifest.rev = mkDefault "refs/heads/${LineageOSRelease}";
}
{
  # split by _, drop android, join by "/"
  # or mkDefault on device == name?
  #
  # (roomservice ends up searching on the github api...)
  # It searches for `android_device_*_${device}
  # Then it runs through the `lineage.dependencies`.
  #  * https://github.com/LineageOS/android_device_sony_pioneer/blob/lineage-17.0/lineage.dependencies
  #  * https://github.com/LineageOS/android_device_sony_nile-common/blob/lineage-17.0/lineage.dependencies
  #
  # It does so recursively...
  #
  # We *probably* want to limit ourselves to the list from hudson
  #  * https://github.com/LineageOS/hudson/blob/master/updater/device_deps.json
  #
  # Otherwise it's 921 (and counting) repos.
  # 
  # OR alternatively make it trivial to just fetch your own device's repo.
  #
  source.dirs = {
    "device/sony/nile-common" = {
      groups = [];
      rev = "90901dffcd85d1655035946d239a346cf198d3ca";
      revisionExpr = "refs/heads/lineage-17.0";
      sha256 = "0998b59p3840brccyajlkqv9w5sfb3a9b3g57zyac03l3625kxhm";
      url = "https://github.com/LineageOS/android_device_sony_nile-common";
    };
    "device/sony/pioneer" = {
      groups = [];
      rev = "ee3b99833ff82194dc5b3d5ae86ac4fe678b4ffe";
      revisionExpr = "refs/heads/lineage-17.0";
      sha256 = "0khfbnfwwx4sxllcmjm9dqa63havlvlymbm1vzm7bfz7fq4d6xib";
      url = "https://github.com/LineageOS/android_device_sony_pioneer";
    };
    "hardware/sony/macaddrsetup" = {
      groups = [];
      rev = "96540129acf7e1e947771a8fd30f2ff350623ffc";
      revisionExpr = "refs/heads/lineage-17.0";
      sha256 = "08pd94fc1z7s1q2rpvclmcawhxf2vhhlaq27y7jqcrys6j3zdc0v";
      url = "https://github.com/LineageOS/android_hardware_sony_macaddrsetup";
    };
    "hardware/sony/simdetect" = {
      groups = [];
      rev = "0f40dea301d470510d9a33afe53b4e46c18407a7";
      revisionExpr = "refs/heads/lineage-17.0";
      sha256 = "1i8w6kij8860bcgcz07ida3rlj54b483d3km4fx3mc01xdklw6gr";
      url = "https://github.com/LineageOS/android_hardware_sony_simdetect";
    };
    "kernel/sony/sdm660" = {
      groups = [];
      rev = "c80a6a3bf5fdfc503571ad3ce725958258563b1e";
      revisionExpr = "refs/heads/lineage-17.0";
      sha256 = "16n9vsp47a4q5w49lsmm9lypq2vz67mysqp4ni5i4bs6kmv8q1na";
      url = "https://github.com/LineageOS/android_kernel_sony_sdm660";
    };
    # And muppets!
    "vendor/sony" = {
      groups = [];
      rev = "f5fe5ee2def78489fe98307d3c1e0f7ac5c9cca5";
      revisionExpr = "refs/heads/lineage-17.0";
      sha256 = "1cf1nr9zcvnswkzc197kzfiafy3jm0gh06dvyfzdfds4rdjkqzhy";
      url = "https://github.com/TheMuppets/proprietary_vendor_sony";
    };
  };
}
])
