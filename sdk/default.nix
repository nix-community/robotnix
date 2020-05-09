(import ../default.nix {
  configuration = {
    productName = "sdk"; # Alternatives are sdk_arm64, sdk_x86_64, sdk_x86
    variant = "eng";
    # TODO: Find out what tag the upstream SDK was built with
    source.dirs = builtins.fromJSON (builtins.readFile ../flavors/vanilla/repo-android-10.0.0_r35.json);
    buildNumber = "eng.10.0.0_r35";
  };
}).build.mkAndroid {
  name = "android-sdk";
  makeTargets = [ "sdk" "sdk_repo" ];
  installPhase = ''
    mkdir -p $out
    cp --reflink=auto out/host/linux-x86/sdk/sdk/*.{zip,xml} $out
  '';
}

## TODO: Unify with checkAndroid above
#checkSdk = mkAndroid {
#  name = "robotnix-check-${config.productName}-${config.buildNumber}";
#  makeTargets = [ "sdk" ];
#  ninjaArgs = "-n"; # Pretend to run the actual build steps
#  # Just copy some things that are useful for debugging
#  installPhase = ''
#    mkdir -p $out
#    cp -r $OUT_DIR/*.{log,gz} $out/
#    cp -r $OUT_DIR/.module_paths $out/
#  '';
#};
