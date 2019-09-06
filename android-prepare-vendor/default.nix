{ lib, callPackage, runCommand }:

rec {
  android-prepare-vendor = callPackage ./android-prepare-vendor.nix {};

  buildVendorFiles =
    { device, img, full ? false, timestamp ? 1, buildID ? "nixdroid" }:
    runCommand "vendor-files-${device}" {} ''
      ${android-prepare-vendor}/execute-all.sh ${lib.optionalString full "--full"} --yes --output $out --device "${device}" --buildID "${buildID}" -i "${img}" --debugfs --timestamp "${builtins.toString timestamp}"
    '';

  unpackImg =
    { device, img }:
    runCommand "unpacked-img-${device}" {} ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-factory-images.sh --debugfs --input "${img}" --output $out --conf-file ${android-prepare-vendor}/${device}/config.json
    '';
}
