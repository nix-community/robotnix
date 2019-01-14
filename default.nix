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
    sha256 = "0y3bl8iinkq91r86zgr59bklvr814fzrnzf2w84k6xsh2mnpn8yg";
    localManifests = [ (./roomservice- + "${device}.xml") ];
      #  ++ lib.optional enableWireguard [ "./wireguard.xml" ];
    # repoRepoURL ? ""
    # repoRepoRev ? ""
    # referenceDir ? ""
  };

  buildPhase = ''cat << W8M8 | ${los-env}/bin/los-build
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
    cd out/target/product/${device}/
    mkdir -p $out
    cp lineage-${release}-*-${device}.zip $out/
    exit
  '';
}
