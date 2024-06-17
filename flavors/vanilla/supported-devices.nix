# SPDX-FileCopyrightText: 2021 Daniel Fullmer
# SPDX-License-Identifier: MIT
{ lib, config }:
let
  # https://source.android.com/setup/start/build-numbers
  phoneDeviceFamilies =
    (lib.optional (config.androidVersion <= 10) "marlin")
    ++ (lib.optionals (config.androidVersion <= 11) [
      "taimen"
      "muskie"
    ])
    ++ [
      "crosshatch"
      "bonito"
      "coral"
      "sunfish"
      "redfin"
      "barbet"
      "raviole"
    ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];
in
{
  inherit phoneDeviceFamilies supportedDeviceFamilies;
}
