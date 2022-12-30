# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ lib, stdenv, buildGoModule, fetchgit, fetchhg, fetchbzr, fetchsvn }:

buildGoModule rec {
  name = "cipd-${version}";
  version = "2022-12-28";
  rev = "85390a103024a9150132156400908c7694265e31";

  subPackages = [ "cipd/client/cmd/cipd" ];

  vendorSha256 = "sha256-fbjl0XYWo4wCt4KjESoFBC8nRXDLNq0IsIpHQx8LhuA=";

  src = fetchgit {
    inherit rev;
    url = "https://chromium.googlesource.com/infra/luci/luci-go";
    sha256 = "sha256-24G3pwKF7AR75sHXLFTwdjOg4dU7X5gKB5sdw0lDPRY=";
  };

  meta = with lib; {
    description = "Chrome Infrastructure Package Deployment";
    longDescription = ''
      CIPD is package deployment infrastructure. It consists of a package
      registry and a CLI client to create, upload, download, and install
      packages.
    '';
    homepage = "https://chromium.googlesource.com/infra/luci/luci-go/+/refs/heads/master/cipd/";
    license = licenses.asl20;
    maintainers = with maintainers; [ danielfullmer ];
    platforms = with platforms; linux ++ darwin;
  };
}
