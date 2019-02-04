{
  pkgs ? import <nixpkgs> {},
  device ? "payton",
  rom ? "lineage",
  rev ? "${rom}-16.0",
  enableWireguard ? false,
  manifest ? "https://github.com/LineageOS/android.git",
  sha256 ? "0iqjqi2vwi6lfrk0034fdb1v8927g0vak2qanljw6hvcad0fid6r"
}:

with pkgs;
let
  nixdroid-env = callPackage ./buildenv.nix {};
in stdenv.mkDerivation rec {
  name = "nixdroid-${rev}-${device}";
  src = fetchRepoProject rec {
    inherit name manifest sha256 rev;
    localManifests = [ (./roomservice- + "${device}.xml") ];
      #  ++ lib.optional enableWireguard [ "./wireguard.xml" ];
    # repoRepoURL ? ""
    # repoRepoRev ? ""
    # referenceDir ? ""
  };

  buildPhase = ''cat << hack | ${nixdroid-env}/bin/nixdroid-build
    export LANG=C
    export ANDROID_JAVA_HOME="${pkgs.jdk.home}"
    export BUILD_NUMBER="$(date --utc +%Y.%m.%d.%H.%M.%S)"
    export DISPLAY_BUILD_NUMBER=true
    export ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G"
    # for jack
    export HOME="$PWD"
    export USER="$(id -un)"

    source build/envsetup.sh
    breakfast "${device}"
    croot
    time brunch "${device}"
    exit
  '';

  installPhase = ''
    mkdir -p "$out/misc"
    cd "out/target/product/${device}/"
    # copy regular image + md5sum
    cp -v "${rev}-"*"-UNOFFICIAL-${device}.zip"* "$out/"
    # ota file
    cp -v "${rom}_${device}-ota"*".zip" "$out/"
    # partition images
    cp -v *.img kernel "$out/misc/"
  '';
}
