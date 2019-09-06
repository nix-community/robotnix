{ lib, callPackage, runCommand }:

rec {
  android-prepare-vendor = callPackage ./android-prepare-vendor.nix {};

  buildVendorFiles =
    { device, img, full ? false, timestamp ? 1, buildID ? "nixdroid" }:
    runCommand "vendor-files-${device}" {} ''
      ${android-prepare-vendor}/execute-all.sh ${lib.optionalString full "--full"} --yes --output $out --device "${device}" --buildID "${buildID}" -i "${img}" --debugfs --timestamp "${builtins.toString timestamp}"
    '';
}
