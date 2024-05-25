{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    mkMerge
    types
    optionalAttrs
    optionalString
    ;

  driversList = lib.importJSON ./pixel-drivers.json;
  fetchItem =
    type: device: buildID:
    let
      matchingItem =
        lib.findSingle (v: lib.hasInfix "/${type}-${device}-${lib.toLower buildID}-" v.url)
          (throw "no items found for ${type} ${device} drivers")
          (throw "multiple items found for ${type} ${device} drivers")
          driversList;
    in
    pkgs.fetchurl matchingItem;

  unpackDrivers =
    tarball:
    pkgs.runCommand "unpacked-${lib.strings.sanitizeDerivationName tarball.name}" { } ''
      tar xvf ${tarball}

      mkdir -p $out
      tail -n +315 ./extract-*.sh | tar zxv -C $out
    '';

  usesQcomDrivers = config.deviceFamily != "raviole";
in
{
  options = {
    pixel.useUpstreamDriverBinaries = mkOption {
      default = false;
      type = types.bool;
      description = "Use device vendor binaries from https://developers.google.com/android/drivers";
    };
  };

  config = mkMerge [
    (mkIf config.pixel.useUpstreamDriverBinaries {
      assertions = [
        {
          assertion = !config.apv.enable;
          message = "pixel.useUpstreamDriverBinaries and apv.enable must not both be set to true";
        }
      ];

      # Merge qcom and google drivers
      source.dirs =
        {
          "build/make".patches = mkIf (config.androidVersion >= 12) [
            ../12/build_make/0003-Add-option-to-include-prebuilt-images-when-signing-t.patch
          ];

          "vendor/google_devices/${config.device}".src = pkgs.runCommand "${config.device}-vendor" { } (
            ''
              mkdir extracted

              cp -r ${config.build.driversGoogle}/vendor/google_devices/${config.device}/. extracted
              chmod +w -R extracted
            ''
            + optionalString usesQcomDrivers ''
              cp -r ${config.build.driversQcom}/vendor/google_devices/${config.device}/. extracted
            ''
            + optionalString (config.deviceFamily == "raviole") ''
              patch extracted/proprietary/Android.mk ${./raviole-ims-presigned.patch}
            ''
            + ''

              mv extracted $out
            ''
          );
        }
        // optionalAttrs usesQcomDrivers {
          "vendor/qcom/${config.device}".src = "${config.build.driversQcom}/vendor/qcom/${config.device}";
        };
    })
    (mkIf (config.pixel.useUpstreamDriverBinaries && config.deviceFamily == "raviole") {
      signing.prebuiltImages =
        let
          prebuilt =
            partition:
            "${config.source.dirs."vendor/google_devices/${config.device}".src}/proprietary/${partition}.img";
        in
        [
          (prebuilt "vendor")
          (prebuilt "vendor_dlkm")
        ];
    })

    ({
      build = {
        driversGoogle = unpackDrivers (fetchItem "google_devices" config.device config.apv.buildID);
        driversQcom = unpackDrivers (fetchItem "qcom" config.device config.apv.buildID);
      };
    })
  ];
}
