(import ../default.nix {
  configuration = {
    buildProduct = "sdk"; # Alternatives are sdk_arm64, sdk_x86_64, sdk_x86
    variant = "userdebug";
    source.dirs = builtins.fromJSON (builtins.readFile ../flavors/vanilla/android-10.0.0_r33.json);
  };
}).build.mkAndroid {
  name = "android-sdk";
  makeTargets = [ "sdk" "sdk_repo" ];
  installPhase = ''
    mkdir -p $out
    cp --reflink=auto out/host/linux-x86/sdk/sdk/*.{zip,xml} $out
  '';
}

## TODO: Unify with checkAndroid abovee
#checkSdk = mkAndroid {
#  name = "robotnix-check-${config.buildProduct}-${config.buildNumber}";
#  makeTargets = [ "sdk" ];
#  ninjaArgs = "-n"; # Pretend to run the actual build steps
#  # Just copy some things that are useful for debugging
#  installPhase = ''
#    mkdir -p $out
#    cp -r $OUT_DIR/*.{log,gz} $out/
#    cp -r $OUT_DIR/.module_paths $out/
#  '';
#};
