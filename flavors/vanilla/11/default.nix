# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault;

  inherit (import ../supported-devices.nix { inherit lib config; })
    supportedDeviceFamilies phoneDeviceFamilies;
in
(mkIf (config.flavor == "vanilla" && config.androidVersion == 11) (mkMerge [
{
  buildDateTime = mkDefault 1631052581;

  source.manifest.rev = mkMerge [
    (mkIf (config.device != "barbet") (mkDefault "android-11.0.0_r43"))
    (mkIf (config.device == "barbet") (mkDefault "android-11.0.0_r44"))
  ];
  apv.buildID = mkMerge [
    (mkIf (config.device != "barbet") (mkDefault "RQ3A.210905.001"))
    (mkIf (config.device == "barbet") (mkDefault "RD2A.210905.002"))
  ];

  # See also: https://github.com/GrapheneOS/os_issue_tracker/issues/325
  # List of biometric sensors on the device, in decreasing strength. Consumed by AuthService
  # when registering authenticators with BiometricService. Format must be ID:Modality:Strength,
  # where: IDs are unique per device, Modality as defined in BiometricAuthenticator.java,
  # and Strength as defined in Authenticators.java
  # TODO: This ought to show up in the vendor (not system or product) resource overlay
  resources."frameworks/base/core/res".config_biometric_sensors = {
    value = optional (elem config.deviceFamily phoneDeviceFamilies) (
              if (config.deviceFamily == "coral") then "0:8:15"
              else "0:2:15");
    type = "string-array";
  };

  # Clock app needs battery optimization exemption. Currently not in AOSP
  source.dirs."packages/apps/DeskClock".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_packages_apps_DeskClock/commit/0b21e707d7dca4c9c3e4ff030bef8fae3abed088.patch";
      sha256 = "0mzjzxyl8g2i520902bhc3ww3vbcwcx06m3zg033z0w6pw87apqc";
    })
  ];
}
(mkIf (elem config.deviceFamily phoneDeviceFamilies) {
  kernel.enable = mkDefault (!(lib.elem config.deviceFamily [ "redfin" "barbet" ]));  # Disable for now until we have it tested working
  kernel.configName = mkMerge [
    (mkIf (elem config.deviceFamily [ "taimen" "muskie" ]) "wahoo")
    (mkIf (config.deviceFamily == "crosshatch") "b1c1")
  ];

  # TODO: Could extract the bind-mounting thing in source.nix into something
  # that works for kernels too. Probably not worth the effort for the payoff
  # though.
  kernel.src = let
    kernelName = if elem config.deviceFamily [ "taimen" "muskie"] then "wahoo" else config.deviceFamily;
    kernelMetadata = (lib.importJSON ./kernel/kernel-metadata.json).${kernelName};
    kernelRepos = lib.importJSON (./kernel + "/repo-${kernelMetadata.branch}.json");
    fetchRepo = repo: pkgs.fetchgit {
      inherit (kernelRepos.${repo}) url rev sha256;
    };
    kernelDirs = {
      "" = fetchRepo "private/msm-google";
    } // optionalAttrs (elem kernelName [ "crosshatch" "bonito" "coral" "sunfish" "redfin" ]) {
      "techpack/audio" = fetchRepo "private/msm-google/techpack/audio";
      "drivers/staging/qca-wifi-host-cmn" = fetchRepo "private/msm-google-modules/wlan/qca-wifi-host-cmn";
      "drivers/staging/qcacld-3.0" = fetchRepo "private/msm-google-modules/wlan/qcacld-3.0";
      "drivers/staging/fw-api" = fetchRepo "private/msm-google-modules/wlan/fw-api";
    } // optionalAttrs (elem kernelName [ "coral" "sunfish" ]) {
      # Sunfish previously used a fts_touch_s5 repo, but it's tag moved back to
      # to regular fts_touch repo, however, the kernel manifest was not updated.
      "drivers/input/touchscreen/fts_touch" = fetchRepo "private/msm-google-modules/touch/fts/floral";
    } // optionalAttrs (elem kernelName [ "redfin" ]) {
      "drivers/input/touchscreen/fts_touch" = fetchRepo "private/msm-google-modules/touch/fts";

      "techpack/audio" = fetchRepo "private/msm-google/techpack/audio";
      "techpack/camera" = fetchRepo "private/msm-google/techpack/camera";
      "techpack/dataipa" = fetchRepo "private/msm-google/techpack/dataipa";
      "techpack/display" = fetchRepo "private/msm-google/techpack/display";
      "techpack/video" = fetchRepo "private/msm-google/techpack/video";
      "drivers/input/touchscreen/sec_touch" = fetchRepo "private/msm-google-modules/touch/sec";
      "arch/arm64/boot/dts/vendor" = fetchRepo "private/msm-google/arch/arm64/boot/dts/vendor";
      "arch/arm64/boot/dts/vendor/qcom/camera" = fetchRepo "private/msm-google/arch/arm64/boot/dts/vendor/qcom/camera";
      "arch/arm64/boot/dts/vendor/qcom/display" = fetchRepo "private/msm-google/arch/arm64/boot/dts/vendor/qcom/display";
    };
  in pkgs.runCommand "kernel-src" {}
    (lib.concatStringsSep "\n" (lib.mapAttrsToList (relpath: repo: ''
      ${lib.optionalString (relpath != "") "mkdir -p $out/$(dirname ${relpath})"}
      cp -r ${repo} $out/${relpath}
      chmod u+w -R $out/${relpath}
    '') kernelDirs));

  kernel.installModules = mkIf (!(elem config.deviceFamily [ "marlin" "taimen" ])) (mkDefault true);
})
(mkIf (elem config.device [ "taimen" "walleye" ]) {
  warnings = [ "taimen and walleye are no longer receiving monthly vendor security updates from Google. Support is left just for testing" ];
  source.manifest.rev = "android-11.0.0_r25"; # More recent sources don't even include device/google/muskie
  apv.buildID = "RP1A.201005.004.A1";
})

]))
