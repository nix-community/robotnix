# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  lib,
  stdenv,
  buildGoPackage,
  fetchgit,
  fetchhg,
  fetchbzr,
  fetchsvn,
}:

buildGoPackage rec {
  name = "cipd-${version}";
  version = "2019-12-13";
  rev = "95480de32ef149429a7a6ab0e5c7380bfb0f102b";

  goPackagePath = "go.chromium.org/luci";
  subPackages = [ "cipd/client/cmd/cipd" ];

  src = fetchgit {
    inherit rev;
    url = "https://chromium.googlesource.com/infra/luci/luci-go";
    sha256 = "0hkg2j4y7vqjhfvlgkfjpc0hcrrb08f6nmz00zxrsf7735lv09i9";
  };

  goDeps = ./deps.nix;

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
    platforms = with platforms; linux;
  };
}
