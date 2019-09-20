{ lib, callPackage, runCommand, api }:

rec {
  android-prepare-vendor = callPackage ./android-prepare-vendor.nix { inherit api; };

  buildVendorFiles =
    { device, img, ota ? null, full ? false, timestamp ? 1, buildID ? "nixdroid", configFile ? null }:
    runCommand "vendor-files-${device}" {} ''
      ${android-prepare-vendor}/execute-all.sh \
        ${lib.optionalString full "--full"} \
        --yes \
        --output . \
        --device "${device}" \
        --buildID "${buildID}" \
        --imgs "${img}" \
        ${lib.optionalString (ota != null) "--ota ${ota}"} \
        --debugfs \
        --timestamp "${builtins.toString timestamp}" \
        ${lib.optionalString (configFile != null) "--conf-file ${configFile}"}

      mkdir -p $out
      cp -r ${device}/${buildID}/* $out
    '';

  unpackImg =
    { device, img, configFile ? null }:
    runCommand "unpacked-img-${device}" {} ''
      mkdir -p $out
      ${android-prepare-vendor}/scripts/extract-factory-images.sh --debugfs --input "${img}" --output $out --conf-file ${android-prepare-vendor}/${device}/config.json
    '';
}
