(import ../default.nix {
  configuration = {
    buildProduct = "sdk";
    variant = "eng";
    flavor = "none";
    source.jsonFile = ./platform-tools-29.0.5.json; # TODO: 29.0.6 is out now
  };
}).build.mkAndroid {
  name = "android-sdk";
  makeTargets = [ "dist" "sdk" "sdk_repo" ];
  installPhase = ''
    #cp --reflink=auto -r $OUT_DIR/host/linux-x86/sdk/sdk/android-sdk_${config.buildNumber}_linux-x86.zip $out
    cp --reflink=auto -r $OUT_DIR/host/linux-x86/sdk/sdk/* $out
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
