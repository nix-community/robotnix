{ pkgs ? import <nixpkgs> {}, device ? "payton", release ? "15.1", enableWireguard ? false }:

with pkgs;
let
  los-env = callPackage ./buildenv.nix {};
in stdenv.mkDerivation rec {
  name = "lineageos-${release}-${device}";
  src = fetchRepoProject rec {
    inherit name;
    manifest = "https://github.com/LineageOS/android.git";
    rev = "lineage-${release}";
    sha256 = "0kwk1cmk7wr26l8znvijh6ryfjs66alz3np34pcgvkd108i90gl4";
    localManifests = [ (./roomservice- + "${device}.xml") ];
      #  ++ lib.optional enableWireguard [ "./wireguard.xml" ];
    # repoRepoURL ? ""
    # repoRepoRev ? ""
    # referenceDir ? ""
  };

  buildPhase = ''cat << hack | ${los-env}/bin/los-build
    export LANG=C
    export ANDROID_JAVA_HOME=${pkgs.jdk.home}
    export BUILD_NUMBER=$(date --utc +%Y.%m.%d.%H.%M.%S)
    export DISPLAY_BUILD_NUMBER=true
    export ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx8G"
    # for jack
    export HOME=$PWD
    export USER=$(id -un)

    source build/envsetup.sh
    breakfast ${device}
    croot
    time brunch ${device}
    exit
  '';

  installPhase = ''
    mkdir -p $out/misc
    cd out/target/product/${device}/
    # copy regular image + md5sum
    cp -v lineage-${release}-*-UNOFFICIAL-${device}.zip* $out/
    # ota file
    cp -v lineage_${device}-ota*.zip $out/
    # partition images
    cp -v *.img kernel $out/misc/
  '';
}
